#!/usr/bin/env bash

set -u -o pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
WORK_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/homelab-local-tests.XXXXXX")
WORK_ROOT=$(cd "$WORK_ROOT" && pwd)
TESTS=0
FAILURES=0

cleanup() {
  rm -rf "$WORK_ROOT"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  FAILURES=$((FAILURES + 1))
}

assert_equal() {
  local description=$1
  local expected=$2
  local actual=$3

  if [[ $actual != "$expected" ]]; then
    fail "$description: expected [$expected], got [$actual]"
    return 1
  fi
}

assert_contains() {
  local description=$1
  local needle=$2
  local haystack=$3

  if [[ $haystack != *"$needle"* ]]; then
    fail "$description: expected output containing [$needle], got [$haystack]"
    return 1
  fi
}

assert_file_absent() {
  local description=$1
  local path=$2

  if [[ -e $path ]]; then
    fail "$description: file exists at [$path]"
    return 1
  fi
}

assert_file_content() {
  local description=$1
  local expected=$2
  local path=$3
  local actual

  if [[ ! -f $path ]]; then
    if [[ ${ASSERT_FILE_CONTENT_PROBE:-0} != 1 ]]; then
      fail "$description: file is missing at [$path]"
    fi
    return 1
  fi

  actual=$(<"$path")
  assert_equal "$description" "$expected" "$actual"
}

commit_laptop_change() {
  local name=$1

  printf '%s\n' "$name" >"$LAPTOP/$name"
  git -C "$LAPTOP" add "$name"
  git -C "$LAPTOP" commit -m "$name" >/dev/null
}

new_fixture() {
  FIXTURE="$WORK_ROOT/$1"
  ORIGIN="$FIXTURE/origin.git"
  SEED="$FIXTURE/seed"
  LAPTOP="$FIXTURE/laptop"
  SERVER="$FIXTURE/server"
  FAKE_BIN="$FIXTURE/bin"
  TAILSCALE_LOG="$FIXTURE/tailscale.log"

  mkdir -p "$SEED/scripts/docker" "$SEED/services/a" "$SEED/services/b" "$FAKE_BIN"
  git init --bare --initial-branch=main "$ORIGIN" >/dev/null
  git init --initial-branch=main "$SEED" >/dev/null
  git -C "$SEED" config user.email test@example.invalid
  git -C "$SEED" config user.name 'Local tests'
  printf 'service: a\n' >"$SEED/services/a/docker-compose.yml"
  printf 'service: b\n' >"$SEED/services/b/docker-compose.yml"
  printf '.deploy-args\n.deploy-fails\n.real-command-ran\n' >"$SEED/.gitignore"
  cat >"$SEED/scripts/docker/deploy.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s' "$*" > .deploy-args
[[ ! -f .deploy-fails ]]
EOF
  cat >"$SEED/scripts/docker/status.sh" <<'EOF'
#!/usr/bin/env bash
printf 'status %s\n' "$*"
EOF
  chmod +x "$SEED/scripts/docker/deploy.sh" "$SEED/scripts/docker/status.sh"

  for path in scripts/local/hl scripts/local/ship.sh Makefile; do
    if [[ -f $ROOT/$path ]]; then
      mkdir -p "$SEED/$(dirname "$path")"
      cp "$ROOT/$path" "$SEED/$path"
      [[ $path == *.sh || $path == */hl ]] && chmod +x "$SEED/$path"
    fi
  done

  git -C "$SEED" add .
  git -C "$SEED" commit -m fixture >/dev/null
  git -C "$SEED" remote add origin "$ORIGIN"
  git -C "$SEED" push -u origin main >/dev/null 2>&1
  git clone "$ORIGIN" "$LAPTOP" >/dev/null 2>&1
  git clone "$ORIGIN" "$SERVER" >/dev/null 2>&1

  cat >"$FAKE_BIN/tailscale" <<'EOF'
#!/usr/bin/env bash
set -u

log=${FAKE_TAILSCALE_LOG:?}
server=${FAKE_SERVER_REPO:?}
[[ $1 == ssh ]] || exit 64
shift
host=$1
shift
printf 'host=%s args=' "$host" >>"$log"
printf '%q ' "$@" >>"$log"
printf '\n' >>"$log"

remote_command=''
if (($#)); then
  remote_command=${!#}
fi

if [[ $remote_command == *true* && ${FAKE_PROBE_MODE:-ok} == fail ]]; then
  exit 255
fi
if [[ $remote_command == *true* && ${FAKE_PROBE_MODE:-ok} == hang ]]; then
  sleep "${FAKE_HANG_SECONDS:-5}"
  exit 0
fi
if [[ -z $remote_command ]]; then
  exit 0
fi

remote_command=${remote_command//\/opt\/homelab/$server}
bash -c "$remote_command"
EOF
  chmod +x "$FAKE_BIN/tailscale"
}

run_from_laptop() {
  local output
  output=$(cd "$LAPTOP" && PATH="$FAKE_BIN:$PATH" FAKE_TAILSCALE_LOG="$TAILSCALE_LOG" FAKE_SERVER_REPO="$SERVER" "$@" 2>&1)
  COMMAND_STATUS=$?
  COMMAND_OUTPUT=$output
}

run_test() {
  if [[ -n ${TEST_FILTER:-} && $1 != "$TEST_FILTER" ]]; then
    return
  fi

  TESTS=$((TESTS + 1))
  "$@"
}

test_fake_tailscale_maps_the_server_path_and_returns_remote_status() {
  # #given
  new_fixture fake-tailscale-contract
  # #when
  FAKE_TAILSCALE_LOG="$TAILSCALE_LOG" FAKE_SERVER_REPO="$SERVER" \
    "$FAKE_BIN/tailscale" ssh seigiard@home -o BatchMode=yes 'touch /opt/homelab/.fake-contract-marker; exit 23'
  local status=$?
  # #then
  assert_equal 'fake tailscale returns the remote command status' '23' "$status" || return
  assert_file_content 'fake tailscale maps the homelab path to the server fixture' '' "$SERVER/.fake-contract-marker"
}

test_hl_preserves_command_semantics() {
  # #given
  new_fixture hl-semantics
  # #when
  run_from_laptop ./scripts/local/hl 'pwd && printf server-value | tr a-z A-Z && exit 23'
  # #then
  assert_equal 'hl forwards the remote exit status' '23' "$COMMAND_STATUS" || return
  assert_contains 'hl runs in the server checkout' "$SERVER" "$COMMAND_OUTPUT" || return
  assert_contains 'hl preserves a pipeline in one command string' 'SERVER-VALUE' "$COMMAND_OUTPUT" || return
  assert_contains 'hl uses the fixed Tailscale host' 'host=seigiard@home' "$(<"$TAILSCALE_LOG")" || return
  assert_contains 'hl uses BatchMode' 'BatchMode=yes' "$(<"$TAILSCALE_LOG")"
}

test_hl_blocks_real_command_when_probe_fails() {
  # #given
  new_fixture hl-probe-failure
  export FAKE_PROBE_MODE=fail
  # #when
  run_from_laptop ./scripts/local/hl 'touch .real-command-ran'
  unset FAKE_PROBE_MODE
  # #then
  [[ $COMMAND_STATUS -ne 0 ]] || { fail 'hl probe failure exits non-zero'; return; }
  assert_contains 'hl explains ACL check mode' 'check' "$COMMAND_OUTPUT" || return
  assert_contains 'hl points to environment documentation' 'ENVIRONMENT.md' "$COMMAND_OUTPUT" || return
  assert_file_absent 'hl does not run the real command after a failed probe' "$SERVER/.real-command-ran"
}

test_hl_blocks_real_command_when_probe_times_out() {
  # #given
  new_fixture hl-probe-timeout
  export FAKE_PROBE_MODE=hang HL_PROBE_TIMEOUT=1 FAKE_HANG_SECONDS=5
  # #when
  SECONDS=0
  run_from_laptop ./scripts/local/hl 'touch .real-command-ran'
  local elapsed=$SECONDS
  unset FAKE_PROBE_MODE HL_PROBE_TIMEOUT FAKE_HANG_SECONDS
  # #then
  [[ $COMMAND_STATUS -ne 0 ]] || { fail 'hl timed-out probe exits non-zero'; return; }
  ((elapsed < 3)) || { fail "hl watchdog ends a probe that would otherwise wait: expected under 3 seconds, got $elapsed"; return; }
  assert_contains 'hl timeout explains the connection problem' 'connection' "$COMMAND_OUTPUT" || return
  assert_file_absent 'hl does not run the real command after a timed-out probe' "$SERVER/.real-command-ran"
}

test_hl_successful_capture_returns_before_probe_timeout() {
  # #given
  new_fixture hl-successful-capture
  export HL_PROBE_TIMEOUT=5
  # #when
  SECONDS=0
  run_from_laptop ./scripts/local/hl 'printf quick-response'
  local elapsed=$SECONDS
  unset HL_PROBE_TIMEOUT
  # #then
  assert_equal 'hl returns the successful remote command status' '0' "$COMMAND_STATUS" || return
  assert_equal 'hl returns the successful remote command output' 'quick-response' "$COMMAND_OUTPUT" || return
  ((elapsed < 3)) || fail "hl closes captured output before its probe timeout: expected under 3 seconds, got $elapsed"
}

test_ship_requires_services() {
  # #given
  new_fixture ship-no-services
  local remote_head
  remote_head=$(git -C "$ORIGIN" rev-parse main)
  commit_laptop_change unpublished-no-services
  # #when
  run_from_laptop ./scripts/local/ship.sh
  # #then
  [[ $COMMAND_STATUS -ne 0 ]] || { fail 'ship without services exits non-zero'; return; }
  assert_contains 'ship without services prints its usage' 'Usage:' "$COMMAND_OUTPUT" || return
  assert_equal 'ship without services does not push' "$remote_head" "$(git -C "$ORIGIN" rev-parse main)"
}

test_ship_rejects_invalid_local_state_before_remote_work() {
  # #given
  new_fixture ship-invalid-local-state
  commit_laptop_change unpublished-non-main
  git -C "$LAPTOP" checkout -b feature >/dev/null
  local remote_head
  remote_head=$(git -C "$ORIGIN" rev-parse main)
  # #when
  run_from_laptop ./scripts/local/ship.sh a
  # #then
  [[ $COMMAND_STATUS -ne 0 ]] || { fail 'ship on a non-main branch exits non-zero'; return; }
  assert_contains 'ship identifies the required local branch' 'main' "$COMMAND_OUTPUT" || return
  assert_equal 'ship on a non-main branch does not push' "$remote_head" "$(git -C "$ORIGIN" rev-parse main)" || return
  assert_file_absent 'ship on a non-main branch makes no server call' "$TAILSCALE_LOG"
}

test_ship_rejects_dirty_local_tree_before_remote_work() {
  # #given
  new_fixture ship-dirty-local-tree
  commit_laptop_change unpublished-dirty-tree
  printf 'dirty\n' >"$LAPTOP/untracked.txt"
  local remote_head
  remote_head=$(git -C "$ORIGIN" rev-parse main)
  # #when
  run_from_laptop ./scripts/local/ship.sh a
  # #then
  [[ $COMMAND_STATUS -ne 0 ]] || { fail 'ship with a dirty local tree exits non-zero'; return; }
  assert_contains 'ship identifies a dirty local tree' 'dirty' "$COMMAND_OUTPUT" || return
  assert_equal 'ship with a dirty local tree does not push' "$remote_head" "$(git -C "$ORIGIN" rev-parse main)" || return
  assert_file_absent 'ship with a dirty local tree makes no server call' "$TAILSCALE_LOG" || return

}

test_ship_rejects_unknown_service_before_remote_work() {
  # #given
  new_fixture ship-unknown-service
  local remote_head
  remote_head=$(git -C "$ORIGIN" rev-parse main)
  commit_laptop_change unpublished-unknown-service
  # #when
  run_from_laptop ./scripts/local/ship.sh missing
  # #then
  [[ $COMMAND_STATUS -ne 0 ]] || { fail 'ship with an unknown service exits non-zero'; return; }
  assert_contains 'ship identifies the missing service compose file' 'missing' "$COMMAND_OUTPUT" || return
  assert_equal 'ship with an unknown service does not push' "$remote_head" "$(git -C "$ORIGIN" rev-parse main)"
}

test_ship_refuses_to_deploy_when_server_head_differs_after_pull() {
  # #given
  new_fixture ship-server-head-mismatch
  local server_origin="$FIXTURE/server-origin.git"
  git init --bare --initial-branch=main "$server_origin" >/dev/null
  git -C "$SEED" push "$server_origin" main >/dev/null 2>&1
  git -C "$SERVER" remote set-url origin "$server_origin"
  commit_laptop_change unpublished-server-head-mismatch
  # #when
  run_from_laptop ./scripts/local/ship.sh a
  # #then
  [[ $COMMAND_STATUS -ne 0 ]] || { fail 'ship with a mismatched server HEAD exits non-zero'; return; }
  assert_contains 'ship reports the server and local HEAD mismatch' 'does not match local HEAD' "$COMMAND_OUTPUT" || return
  assert_file_absent 'ship does not deploy when the server HEAD differs after pull' "$SERVER/.deploy-args"
}

test_ship_rejects_dirty_server_without_reset_or_deploy() {
  # #given
  new_fixture ship-dirty-server
  printf 'keep me\n' >"$SERVER/untracked.txt"
  local server_head
  server_head=$(git -C "$SERVER" rev-parse HEAD)
  # #when
  run_from_laptop ./scripts/local/ship.sh a
  # #then
  [[ $COMMAND_STATUS -ne 0 ]] || { fail 'ship with a dirty server exits non-zero'; return; }
  assert_contains 'ship prints server porcelain output' '?? untracked.txt' "$COMMAND_OUTPUT" || return
  assert_contains 'ship prints the manual reset command' 'git reset --hard' "$COMMAND_OUTPUT" || return
  assert_equal 'ship leaves the dirty server HEAD unchanged' "$server_head" "$(git -C "$SERVER" rev-parse HEAD)" || return
  assert_file_content 'ship leaves the untracked server file unchanged' 'keep me' "$SERVER/untracked.txt" || return
  assert_file_absent 'ship does not deploy from a dirty server' "$SERVER/.deploy-args"
}

test_ship_pushes_pulls_and_deploys_each_time() {
  # #given
  new_fixture ship-success
  printf 'changed: true\n' >>"$LAPTOP/services/a/docker-compose.yml"
  git -C "$LAPTOP" add services/a/docker-compose.yml
  git -C "$LAPTOP" commit -m change >/dev/null
  # #when
  run_from_laptop ./scripts/local/ship.sh a b
  # #then
  assert_equal 'ship succeeds after pushing a change' '0' "$COMMAND_STATUS" || return
  assert_equal 'ship updates the server to the local HEAD' "$(git -C "$LAPTOP" rev-parse HEAD)" "$(git -C "$SERVER" rev-parse HEAD)" || return
  assert_file_content 'ship deploys the requested services in order' 'a b' "$SERVER/.deploy-args" || return
  assert_contains 'ship prints the server HEAD' "$(git -C "$SERVER" rev-parse HEAD)" "$COMMAND_OUTPUT" || return
  assert_contains 'ship prints the shipped service status' 'status a b' "$COMMAND_OUTPUT" || return

  rm "$SERVER/.deploy-args"
  run_from_laptop ./scripts/local/ship.sh a b
  assert_equal 'ship re-deploys when there is nothing new to push' '0' "$COMMAND_STATUS" || return
  assert_file_content 'ship re-deploys all requested services' 'a b' "$SERVER/.deploy-args"
}

test_ship_reports_status_after_deploy_failure() {
  # #given
  new_fixture ship-deploy-failure
  touch "$SERVER/.deploy-fails"
  assert_equal 'fixture deploy markers do not dirty the server tree' '' "$(git -C "$SERVER" status --porcelain)" || return
  # #when
  run_from_laptop ./scripts/local/ship.sh a
  # #then
  [[ $COMMAND_STATUS -ne 0 ]] || { fail 'ship exits non-zero when deploy fails'; return; }
  assert_file_content 'ship attempts the requested deploy before reporting failure' 'a' "$SERVER/.deploy-args" || return
  assert_contains 'ship still prints the server HEAD after deploy fails' "$(git -C "$SERVER" rev-parse HEAD)" "$COMMAND_OUTPUT" || return
  assert_contains 'ship still prints shipped service status after deploy fails' 'status a' "$COMMAND_OUTPUT"
}

test_make_ship_forwards_services_and_rejects_empty_value() {
  # #given
  new_fixture make-ship
  mkdir -p "$LAPTOP/scripts/local"
  cat >"$LAPTOP/scripts/local/ship.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > .make-ship-args
EOF
  chmod +x "$LAPTOP/scripts/local/ship.sh"
  # #when
  run_from_laptop make ship 'SVC=a b'
  # #then
  assert_equal 'make ship succeeds with services' '0' "$COMMAND_STATUS" || return
  assert_file_content 'make ship forwards each service to ship.sh' $'a\nb' "$LAPTOP/.make-ship-args" || return

  rm "$LAPTOP/.make-ship-args"
  run_from_laptop make ship
  [[ $COMMAND_STATUS -ne 0 ]] || { fail 'make ship without SVC exits non-zero'; return; }
  assert_file_absent 'make ship without SVC does not run ship.sh' "$LAPTOP/.make-ship-args"
}

test_assert_file_content_rejects_a_missing_file() {
  # #given
  new_fixture assert-file-content-missing
  # #when
  export ASSERT_FILE_CONTENT_PROBE=1
  assert_file_content 'assert_file_content missing-file control' '' "$SERVER/missing-file"
  local status=$?
  unset ASSERT_FILE_CONTENT_PROBE
  # #then
  assert_equal 'assert_file_content fails when its file is missing' '1' "$status"
}

run_test test_fake_tailscale_maps_the_server_path_and_returns_remote_status
run_test test_hl_preserves_command_semantics
run_test test_hl_blocks_real_command_when_probe_fails
run_test test_hl_blocks_real_command_when_probe_times_out
run_test test_hl_successful_capture_returns_before_probe_timeout
run_test test_ship_requires_services
run_test test_ship_rejects_invalid_local_state_before_remote_work
run_test test_ship_rejects_dirty_local_tree_before_remote_work
run_test test_ship_rejects_unknown_service_before_remote_work
run_test test_ship_rejects_dirty_server_without_reset_or_deploy
run_test test_ship_refuses_to_deploy_when_server_head_differs_after_pull
run_test test_ship_pushes_pulls_and_deploys_each_time
run_test test_ship_reports_status_after_deploy_failure
run_test test_make_ship_forwards_services_and_rejects_empty_value
run_test test_assert_file_content_rejects_a_missing_file

if ((FAILURES)); then
  printf '%s of %s local tests failed\n' "$FAILURES" "$TESTS" >&2
  exit 1
fi

printf 'ok - %s local tests passed\n' "$TESTS"
