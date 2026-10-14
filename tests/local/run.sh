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

assert_table_cell() {
    local description=$1
    local expected=$2
    local column=$3
    local line=$4
    local actual

    actual=$(printf '%s\n' "$line" | awk -v column="$column" '{print $column}')
    assert_equal "$description" "$expected" "$actual"
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

new_container_drift_fixture() {
  DRIFT_FIXTURE="$WORK_ROOT/$1"
  DRIFT_BIN="$DRIFT_FIXTURE/bin"
  DRIFT_CONTAINERS="$DRIFT_FIXTURE/containers.json"
  DRIFT_IMAGES="$DRIFT_FIXTURE/images.json"
  DRIFT_STATE="$DRIFT_FIXTURE/state.json"
  DRIFT_CURL_LOG="$DRIFT_FIXTURE/curl.log"

  mkdir -p "$DRIFT_BIN"
  cp "$ROOT/tests/local/fixtures/container-drift-initial.json" "$DRIFT_CONTAINERS"
  cp "$ROOT/tests/local/fixtures/container-drift-images.json" "$DRIFT_IMAGES"

  cat >"$DRIFT_BIN/docker" <<'EOF'
#!/usr/bin/env bash
set -eu

containers=${FAKE_DOCKER_CONTAINERS:?}
images=${FAKE_DOCKER_IMAGES:?}

case ${1:-} in
  ps)
    shift
    all=false
    project=''
    while (($#)); do
      case $1 in
        -a)
          all=true
          shift
          ;;
        -q)
          shift
          ;;
        --filter)
          project=${2#label=com.docker.compose.project=}
          shift 2
          ;;
        *)
          exit 64
          ;;
      esac
    done
    if [[ -n $project ]]; then
      jq -r --argjson all "$all" --arg project "$project" \
        '.[] | select($all or (.State.Status == "running" or .State.Status == "restarting")) | select(.Config.Labels["com.docker.compose.project"] == $project) | .Id' "$containers"
    else
      if [[ -n ${FAKE_DOCKER_VANISHED_ID:-} ]]; then
        printf '%s\n' "$FAKE_DOCKER_VANISHED_ID"
      fi
      jq -r --argjson all "$all" \
        '.[] | select($all or (.State.Status == "running" or .State.Status == "restarting")) | .Id' "$containers"
    fi
    ;;
  inspect)
    shift
    for id in "$@"; do
      if [[ ${FAKE_DOCKER_VANISHED_ID:-} == "$id" ]] || ! jq -e --arg id "$id" 'any(.[]; .Id == $id)' "$containers" >/dev/null; then
        printf 'Error: No such object: %s\n' "$id" >&2
        exit 1
      fi
    done
    jq -c --args '$ARGS.positional as $ids | [.[] | select(.Id as $id | $ids | index($id))]' "$@" <"$containers"
    ;;
  image)
    [[ ${2:-} == inspect ]] || exit 64
    shift 2
    jq -c --args '$ARGS.positional as $ids | [.[] | select(.Id as $id | $ids | index($id))]' "$@" <"$images"
    ;;
  *)
    exit 64
    ;;
esac
EOF
  chmod +x "$DRIFT_BIN/docker"

  cat >"$DRIFT_BIN/curl" <<'EOF'
#!/usr/bin/env bash
set -eu

body=''
url=''
method=''
has_body=false

read_body() {
  if [[ $1 == @- ]]; then
    cat
  else
    printf '%s' "$1"
  fi
}

while (($#)); do
  case $1 in
    -d|--data|--data-binary|--json)
      value=$2
      shift 2
      body=$(read_body "$value")
      has_body=true
      ;;
    --data=*|--data-binary=*|--json=*)
      body=$(read_body "${1#*=}")
      has_body=true
      shift
      ;;
    -X|--request)
      method=$2
      shift 2
      ;;
    --request=*)
      method=${1#*=}
      shift
      ;;
    -G|--get)
      method=GET
      shift
      ;;
    -H|--header)
      shift 2
      ;;
    -*)
      shift
      ;;
    *)
      url=$1
      shift
      ;;
  esac
done

if [[ -z $method ]]; then
  if [[ $has_body == true ]]; then
    method=POST
  else
    method=GET
  fi
fi

printf '%s\t%s\t%s\n' "$method" "$url" "$body" >>"${FAKE_CURL_LOG:?}"
if [[ -n ${FAKE_CURL_FAIL_EVENT:-} && $(printf '%s' "$body" | jq -r '.event') == "$FAKE_CURL_FAIL_EVENT" ]]; then
  exit "${FAKE_CURL_FAILURE_STATUS:-22}"
fi
exit "${FAKE_CURL_STATUS:-0}"
EOF
  chmod +x "$DRIFT_BIN/curl"

  cat >"$DRIFT_BIN/logger" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$DRIFT_BIN/logger"
}

use_container_drift_snapshot() {
  cp "$ROOT/tests/local/fixtures/$1" "$DRIFT_CONTAINERS"
}

run_container_drift_watch() {
  local output
  output=$(PATH="$DRIFT_BIN:$PATH" FAKE_DOCKER_CONTAINERS="$DRIFT_CONTAINERS" FAKE_DOCKER_IMAGES="$DRIFT_IMAGES" \
    FAKE_CURL_LOG="$DRIFT_CURL_LOG" CONTAINER_DRIFT_STATE="$DRIFT_STATE" \
    HA_WEBHOOK_URL='http://ha.example.invalid/api/webhook/homelab-container-drift' \
    bash "$ROOT/scripts/container-drift-watch.sh" 2>&1)
  COMMAND_STATUS=$?
  COMMAND_OUTPUT=$output
}

run_container_drift_watch_at() {
  CONTAINER_DRIFT_NOW=$1 run_container_drift_watch
}

run_docker_status() {
  local output
  output=$(PATH="$DRIFT_BIN:$PATH" FAKE_DOCKER_CONTAINERS="$DRIFT_CONTAINERS" FAKE_DOCKER_IMAGES="$DRIFT_IMAGES" \
    bash "$ROOT/scripts/docker/status.sh" "$@" 2>&1)
  COMMAND_STATUS=$?
  COMMAND_OUTPUT=$output
}

assert_webhook_event() {
  local description=$1
  local expected_container=$2
  local expected_event=$3
  local expected_request=$4
  local request=0 method='' url='' body='' found=false

  [[ -f $DRIFT_CURL_LOG ]] || { fail "$description: webhook was not called"; return 1; }

  while IFS=$'\t' read -r method url body; do
    request=$((request + 1))
    if [[ $request == "$expected_request" ]]; then
      found=true
      break
    fi
  done <"$DRIFT_CURL_LOG"

  [[ $found == true ]] || { fail "$description: expected request $expected_request, got $request request(s)"; return 1; }

  assert_equal "$description method" 'POST' "$method" || return
  assert_equal "$description URL" 'http://ha.example.invalid/api/webhook/homelab-container-drift' "$url" || return
  assert_equal "$description event fields" "{\"container\":\"$expected_container\",\"event\":\"$expected_event\"}" "$(printf '%s' "$body" | jq -c '{container, event}')" || return
  assert_equal "$description message" 'present' "$(printf '%s' "$body" | jq -r 'if ((.message | type) == "string" and (.message | length) > 0) then "present" else "missing" end')"
}

assert_webhook_count() {
  local description=$1
  local expected=$2
  local actual=0

  if [[ -f $DRIFT_CURL_LOG ]]; then
    actual=$(wc -l <"$DRIFT_CURL_LOG" | tr -d ' ')
  fi

  assert_equal "$description" "$expected" "$actual"
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
  commit_laptop_change unpublished-dirty-server
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

test_container_drift_fake_docker_matches_the_consumed_cli_boundary() {
  # #given
  new_container_drift_fixture container-drift-fake-docker
  # #when
  local container_ids running_container_ids inspect_output image_output
  container_ids=$(FAKE_DOCKER_CONTAINERS="$DRIFT_CONTAINERS" FAKE_DOCKER_IMAGES="$DRIFT_IMAGES" "$DRIFT_BIN/docker" ps -a -q --filter label=com.docker.compose.project=alpha)
  running_container_ids=$(FAKE_DOCKER_CONTAINERS="$DRIFT_CONTAINERS" FAKE_DOCKER_IMAGES="$DRIFT_IMAGES" "$DRIFT_BIN/docker" ps -q)
  inspect_output=$(FAKE_DOCKER_CONTAINERS="$DRIFT_CONTAINERS" FAKE_DOCKER_IMAGES="$DRIFT_IMAGES" "$DRIFT_BIN/docker" inspect alpha-container-id)
  image_output=$(FAKE_DOCKER_CONTAINERS="$DRIFT_CONTAINERS" FAKE_DOCKER_IMAGES="$DRIFT_IMAGES" "$DRIFT_BIN/docker" image inspect sha256:1111111111111111111111111111111111111111111111111111111111111111)
  # #then
  assert_equal 'fake docker filters compose projects' 'alpha-container-id' "$container_ids" || return
  assert_equal 'fake docker lists exited containers only with -a' 'alpha-container-id' "$running_container_ids" || return
  assert_equal 'fake docker inspect returns Docker JSON arrays' '139' "$(printf '%s' "$inspect_output" | jq -r '.[0].State.ExitCode')" || return
  assert_equal 'fake docker image inspect returns image creation time' '2026-10-01T00:00:00.000000000Z' "$(printf '%s' "$image_output" | jq -r '.[0].Created')"
}

test_assert_webhook_event_rejects_a_wrong_event() {
  # #given
  new_container_drift_fixture assert-webhook-event-wrong-event
  printf '%s\t%s\t%s\n' 'POST' 'http://ha.example.invalid/api/webhook/homelab-container-drift' '{"container":"alpha","event":"restarts","message":"restart count grew"}' >"$DRIFT_CURL_LOG"
  local failures_before=$FAILURES
  # #when
  assert_webhook_event 'webhook assertion wrong-event control' alpha image 1 2>/dev/null
  local status=$?
  FAILURES=$failures_before
  # #then
  assert_equal 'webhook assertion rejects the wrong event' '1' "$status"
}

test_assert_webhook_event_accepts_the_webhook_contract() {
  # #given
  new_container_drift_fixture assert-webhook-event-contract
  printf '%s\t%s\t%s\n' 'POST' 'http://ha.example.invalid/api/webhook/homelab-container-drift' '{"container":"alpha","event":"restarts","message":"restart count grew"}' >"$DRIFT_CURL_LOG"
  # #when
  assert_webhook_event 'webhook assertion contract control' alpha restarts 1
  local status=$?
  # #then
  assert_equal 'webhook assertion accepts a contract post' '0' "$status"
}

test_assert_table_cell_requires_the_expected_column() {
  # #given
  local line='alpha restarting 6157 139 111111111111 2026-10-01T00:00:00.000000000Z'
  local failures_before=$FAILURES
  # #when
  assert_table_cell 'table cell valid control' 6157 3 "$line"
  local valid_status=$?
  assert_table_cell 'table cell wrong-value control' 6158 3 "$line" 2>/dev/null
  local wrong_status=$?
  assert_table_cell 'table cell wrong-column control' 6157 4 "$line" 2>/dev/null
  local wrong_column_status=$?
  FAILURES=$failures_before
  # #then
  assert_equal 'table cell accepts the expected value in its column' '0' "$valid_status" || return
  assert_equal 'table cell rejects a nearby wrong value' '1' "$wrong_status" || return
  assert_equal 'table cell rejects a value from a different column' '1' "$wrong_column_status"
}

test_assert_webhook_count_requires_the_exact_request_count() {
  # #given
  new_container_drift_fixture assert-webhook-count
  printf '%s\t%s\t%s\n' 'POST' 'http://ha.example.invalid/api/webhook/homelab-container-drift' '{"container":"alpha","event":"restarts","message":"restart count grew"}' >"$DRIFT_CURL_LOG"
  local failures_before=$FAILURES
  # #when
  assert_webhook_count 'webhook count valid control' 1
  local valid_status=$?
  assert_webhook_count 'webhook count wrong-value control' 2 2>/dev/null
  local wrong_status=$?
  FAILURES=$failures_before
  # #then
  assert_equal 'webhook count accepts the exact request count' '0' "$valid_status" || return
  assert_equal 'webhook count rejects a different request count' '1' "$wrong_status"
}

test_assert_webhook_event_rejects_a_wrong_method() {
  # #given
  new_container_drift_fixture assert-webhook-event-wrong-method
  printf '%s\t%s\t%s\n' 'GET' 'http://ha.example.invalid/api/webhook/homelab-container-drift' '{"container":"alpha","event":"restarts","message":"restart count grew"}' >"$DRIFT_CURL_LOG"
  local failures_before=$FAILURES
  # #when
  assert_webhook_event 'webhook assertion wrong-method control' alpha restarts 1 2>/dev/null
  local status=$?
  FAILURES=$failures_before
  # #then
  assert_equal 'webhook assertion rejects a non-POST request' '1' "$status"
}

test_fake_curl_records_json_request_bodies() {
  # #given
  new_container_drift_fixture fake-curl-json
  local request expected
  request='{"container":"alpha","event":"restarts","message":"restart count grew"}'
  expected=$(printf 'POST\t%s\t%s\nPOST\t%s\t%s' \
    'http://ha.example.invalid/api/webhook/homelab-container-drift' "$request" \
    'http://ha.example.invalid/api/webhook/homelab-container-drift' "$request")
  # #when
  FAKE_CURL_LOG="$DRIFT_CURL_LOG" "$DRIFT_BIN/curl" --json "$request" http://ha.example.invalid/api/webhook/homelab-container-drift
  local inline_status=$?
  printf '%s' "$request" | FAKE_CURL_LOG="$DRIFT_CURL_LOG" "$DRIFT_BIN/curl" --json @- http://ha.example.invalid/api/webhook/homelab-container-drift
  local stdin_status=$?
  # #then
  assert_equal 'fake curl accepts an inline --json body' '0' "$inline_status" || return
  assert_equal 'fake curl accepts a stdin --json body' '0' "$stdin_status" || return
  assert_file_content 'fake curl records inline and stdin --json bodies' "$expected" "$DRIFT_CURL_LOG"
}

test_docker_status_shows_container_drift_columns_and_filters_services() {
  # #given
  new_container_drift_fixture docker-status-columns
  # #when
  run_docker_status
  # #then
  assert_equal 'docker status succeeds for every container' '0' "$COMMAND_STATUS" || return
  local header alpha_line beta_line
  header=$(printf '%s\n' "$COMMAND_OUTPUT" | grep -F NAME)
  alpha_line=$(printf '%s\n' "$COMMAND_OUTPUT" | grep -F alpha)
  beta_line=$(printf '%s\n' "$COMMAND_OUTPUT" | grep -F beta)
  assert_equal 'docker status labels columns in output order' 'NAME STATE RESTARTS EXIT CODE IMAGE ID IMAGE CREATED' "$(printf '%s\n' "$header" | awk '{$1=$1; print}')" || return
  assert_table_cell 'docker status prints alpha state under STATE' 'restarting' 2 "$alpha_line" || return
  assert_table_cell 'docker status prints alpha restart count under RESTARTS' '6157' 3 "$alpha_line" || return
  assert_table_cell 'docker status prints alpha exit code under EXIT CODE' '139' 4 "$alpha_line" || return
  assert_table_cell 'docker status prints alpha short image ID under IMAGE ID' '111111111111' 5 "$alpha_line" || return
  assert_table_cell 'docker status prints alpha image creation time under IMAGE CREATED' '2026-10-01T00:00:00.000000000Z' 6 "$alpha_line" || return
  assert_table_cell 'docker status prints beta state under STATE' 'exited' 2 "$beta_line" || return
  assert_table_cell 'docker status prints beta restart count under RESTARTS' '42' 3 "$beta_line" || return
  assert_table_cell 'docker status prints beta exit code under EXIT CODE' '3' 4 "$beta_line" || return
  assert_table_cell 'docker status prints beta short image ID under IMAGE ID' '333333333333' 5 "$beta_line" || return
  assert_table_cell 'docker status prints beta image creation time under IMAGE CREATED' '2026-09-30T00:00:00.000000000Z' 6 "$beta_line" || return

  run_docker_status alpha
  assert_equal 'docker status succeeds for a selected service' '0' "$COMMAND_STATUS" || return
  assert_contains 'docker status keeps the selected service' 'alpha' "$COMMAND_OUTPUT" || return
  assert_equal 'docker status omits other services when filtered' 'absent' "$(if [[ $COMMAND_OUTPUT == *beta* ]]; then printf present; else printf absent; fi)"
}

test_docker_status_skips_a_container_that_vanishes_during_inspect() {
  # #given
  new_container_drift_fixture docker-status-vanished-container
  export FAKE_DOCKER_VANISHED_ID=vanished-container-id
  # #when
  run_docker_status
  unset FAKE_DOCKER_VANISHED_ID
  # #then
  assert_equal 'docker status succeeds when one listed container vanishes' '0' "$COMMAND_STATUS" || return
  assert_contains 'docker status prints other containers after an inspect race' 'alpha' "$COMMAND_OUTPUT" || return
  assert_contains 'docker status prints every remaining container after an inspect race' 'beta' "$COMMAND_OUTPUT"
}

test_container_drift_notifies_when_restart_count_grows() {
  # #given
  new_container_drift_fixture container-drift-restarts
  run_container_drift_watch
  assert_equal 'container drift first run records state' '0' "$COMMAND_STATUS" || return
  assert_file_absent 'container drift first run does not notify' "$DRIFT_CURL_LOG" || return
  use_container_drift_snapshot container-drift-restarted.json
  # #when
  run_container_drift_watch
  # #then
  assert_equal 'container drift restart notification succeeds' '0' "$COMMAND_STATUS" || return
  assert_webhook_event 'container drift restart notification' alpha restarts 1
}

test_container_drift_notifies_when_image_id_changes() {
  # #given
  new_container_drift_fixture container-drift-image
  run_container_drift_watch
  assert_equal 'container drift first run records image state' '0' "$COMMAND_STATUS" || return
  assert_file_absent 'container drift first run does not notify about images' "$DRIFT_CURL_LOG" || return
  use_container_drift_snapshot container-drift-image-changed.json
  # #when
  run_container_drift_watch
  # #then
  assert_equal 'container drift image notification succeeds' '0' "$COMMAND_STATUS" || return
  assert_webhook_count 'container drift image change sends exactly one webhook' 1 || return
  assert_webhook_event 'container drift image notification' alpha image 1
}

test_container_drift_suppresses_baseline_unchanged_new_and_recreated_containers() {
  # #given
  new_container_drift_fixture container-drift-suppression
  run_container_drift_watch_at 1000000
  assert_equal 'container drift baseline succeeds' '0' "$COMMAND_STATUS" || return
  run_container_drift_watch_at 1000060
  assert_equal 'container drift unchanged scan succeeds' '0' "$COMMAND_STATUS" || return
  use_container_drift_snapshot container-drift-alpha-only.json
  run_container_drift_watch_at 1000120
  assert_equal 'container drift removed-container scan succeeds' '0' "$COMMAND_STATUS" || return
  use_container_drift_snapshot container-drift-reintroduced-beta.json
  run_container_drift_watch_at 1000180
  assert_equal 'container drift reintroduced-container scan succeeds' '0' "$COMMAND_STATUS" || return
  assert_webhook_count 'container drift compares a container reintroduced within the state TTL' 1 || return
  assert_webhook_event 'container drift notifies about a reintroduced container restart' beta restarts 1 || return
  use_container_drift_snapshot container-drift-new-container.json
  run_container_drift_watch_at 1000240
  assert_equal 'container drift new-container scan succeeds' '0' "$COMMAND_STATUS" || return
  assert_webhook_count 'container drift suppresses a new container after reintroduction' 1 || return
  use_container_drift_snapshot container-drift-new-container-restarted.json
  run_container_drift_watch_at 1000300
  assert_equal 'container drift records a new container for the next scan' '0' "$COMMAND_STATUS" || return
  assert_webhook_count 'container drift notifies once after a new container later restarts' 2 || return
  assert_webhook_event 'container drift notifies after a new container later restarts' gamma restarts 2 || return
  use_container_drift_snapshot container-drift-recreated.json
  # #when
  run_container_drift_watch_at 1000360
  # #then
  assert_equal 'container drift recreated-container scan succeeds' '0' "$COMMAND_STATUS" || return
  assert_webhook_count 'container drift does not notify when a restart count drops' 2
}

test_container_drift_notifies_about_restarts_after_a_container_is_recreated() {
  # #given
  new_container_drift_fixture container-drift-recreated-restarts
  run_container_drift_watch
  assert_equal 'container drift baseline before recreation succeeds' '0' "$COMMAND_STATUS" || return
  use_container_drift_snapshot container-drift-recreated-restarted.json
  # #when
  run_container_drift_watch
  # #then
  assert_equal 'container drift recreated-container restart notification succeeds' '0' "$COMMAND_STATUS" || return
  assert_webhook_count 'container drift sends one restart notification after recreation' 1 || return
  assert_webhook_event 'container drift reports restarts from the recreated container' alpha restarts 1
}

test_container_drift_retries_a_failed_webhook_without_advancing_state() {
  # #given
  new_container_drift_fixture container-drift-webhook-retry
  run_container_drift_watch
  assert_equal 'container drift baseline before webhook failure succeeds' '0' "$COMMAND_STATUS" || return
  use_container_drift_snapshot container-drift-restarted.json
  export FAKE_CURL_STATUS=19
  run_container_drift_watch
  unset FAKE_CURL_STATUS
  [[ $COMMAND_STATUS != 0 ]] || { fail "container drift exits non-zero when the webhook fails: got [$COMMAND_STATUS]"; return; }
  # #when
  run_container_drift_watch
  # #then
  assert_equal 'container drift retries a failed webhook' '0' "$COMMAND_STATUS" || return
  assert_equal 'container drift makes a second webhook attempt after failure' '2' "$(wc -l <"$DRIFT_CURL_LOG" | tr -d ' ')" || return
  assert_webhook_event 'container drift retried restart notification' alpha restarts 2
}

test_container_drift_skips_a_container_that_vanishes_during_inspect() {
  # #given
  new_container_drift_fixture container-drift-vanished-container
  run_container_drift_watch
  assert_equal 'container drift baseline before an inspect race succeeds' '0' "$COMMAND_STATUS" || return
  use_container_drift_snapshot container-drift-restarted.json
  export FAKE_DOCKER_VANISHED_ID=vanished-container-id
  # #when
  run_container_drift_watch
  local changed_scan_status=$COMMAND_STATUS
  run_container_drift_watch
  local unchanged_scan_status=$COMMAND_STATUS
  unset FAKE_DOCKER_VANISHED_ID
  # #then
  assert_equal 'container drift succeeds when one listed container vanishes' '0' "$changed_scan_status" || return
  assert_webhook_count 'container drift notifies about the remaining changed container' 1 || return
  assert_webhook_event 'container drift reports the remaining restart after an inspect race' alpha restarts 1 || return
  assert_equal 'container drift unchanged scan after an inspect race succeeds' '0' "$unchanged_scan_status" || return
  assert_webhook_count 'container drift does not repeat a delivered alert after an inspect race' 1
}

test_container_drift_retries_only_a_failed_image_event() {
  # #given
  new_container_drift_fixture container-drift-image-partial-failure
  run_container_drift_watch
  assert_equal 'container drift baseline before an image delivery failure succeeds' '0' "$COMMAND_STATUS" || return
  use_container_drift_snapshot container-drift-restarted-image-changed.json
  export FAKE_CURL_FAIL_EVENT=image
  # #when
  run_container_drift_watch
  unset FAKE_CURL_FAIL_EVENT
  # #then
  [[ $COMMAND_STATUS != 0 ]] || { fail "container drift exits non-zero when only image delivery fails: got [$COMMAND_STATUS]"; return; }
  assert_webhook_count 'container drift attempts both events before an image delivery failure' 2 || return
  assert_webhook_event 'container drift delivers restarts before image delivery fails' alpha restarts 1 || return
  assert_webhook_event 'container drift attempts the image delivery' alpha image 2 || return

  run_container_drift_watch
  assert_equal 'container drift retry after an image delivery failure succeeds' '0' "$COMMAND_STATUS" || return
  assert_webhook_count 'container drift retries only the failed image event' 3 || return
  assert_webhook_event 'container drift retry sends image without duplicating restarts' alpha image 3
}

test_container_drift_retries_only_a_failed_restart_event() {
  # #given
  new_container_drift_fixture container-drift-restart-partial-failure
  run_container_drift_watch
  assert_equal 'container drift baseline before a restart delivery failure succeeds' '0' "$COMMAND_STATUS" || return
  use_container_drift_snapshot container-drift-restarted-image-changed.json
  export FAKE_CURL_FAIL_EVENT=restarts
  # #when
  run_container_drift_watch
  unset FAKE_CURL_FAIL_EVENT
  # #then
  [[ $COMMAND_STATUS != 0 ]] || { fail "container drift exits non-zero when only restart delivery fails: got [$COMMAND_STATUS]"; return; }
  assert_webhook_count 'container drift attempts both events when restart delivery fails' 2 || return
  assert_webhook_event 'container drift attempts the restart delivery' alpha restarts 1 || return
  assert_webhook_event 'container drift still delivers image after restart delivery fails' alpha image 2 || return

  run_container_drift_watch
  assert_equal 'container drift retry after a restart delivery failure succeeds' '0' "$COMMAND_STATUS" || return
  assert_webhook_count 'container drift retries only the failed restart event' 3 || return
  assert_webhook_event 'container drift retry sends restarts without duplicating image' alpha restarts 3
}

test_container_drift_compares_a_container_that_returns_within_the_ttl() {
  # #given
  new_container_drift_fixture container-drift-short-absence
  run_container_drift_watch_at 1000000
  assert_equal 'container drift short-absence baseline succeeds' '0' "$COMMAND_STATUS" || return
  use_container_drift_snapshot container-drift-beta-only.json
  run_container_drift_watch_at 1000060
  assert_equal 'container drift short-absence scan succeeds' '0' "$COMMAND_STATUS" || return
  use_container_drift_snapshot container-drift-image-changed.json
  # #when
  run_container_drift_watch_at 1086399
  # #then
  assert_equal 'container drift short-absence return succeeds' '0' "$COMMAND_STATUS" || return
  assert_webhook_count 'container drift compares an image after an absence shorter than 24 hours' 1 || return
  assert_webhook_event 'container drift reports the image changed during a short absence' alpha image 1
}

test_container_drift_expires_a_container_absent_longer_than_the_ttl() {
  # #given
  new_container_drift_fixture container-drift-long-absence
  run_container_drift_watch_at 2000000
  assert_equal 'container drift long-absence baseline succeeds' '0' "$COMMAND_STATUS" || return
  use_container_drift_snapshot container-drift-beta-only.json
  run_container_drift_watch_at 2000060
  assert_equal 'container drift long-absence scan succeeds' '0' "$COMMAND_STATUS" || return
  run_container_drift_watch_at 2086401
  assert_equal 'container drift expiry scan succeeds' '0' "$COMMAND_STATUS" || return
  assert_equal 'container drift drops a container that stays absent longer than 24 hours' 'true' "$(jq -r 'all(.[]; .name != "alpha")' "$DRIFT_STATE")" || return
  use_container_drift_snapshot container-drift-image-changed.json
  # #when
  run_container_drift_watch_at 2086461
  # #then
  assert_equal 'container drift long-absence return succeeds' '0' "$COMMAND_STATUS" || return
  assert_webhook_count 'container drift treats an image after an absence longer than 24 hours as new' 0
}

test_container_drift_compares_a_present_container_after_a_long_watcher_gap() {
  # #given
  new_container_drift_fixture container-drift-present-long-gap
  run_container_drift_watch_at 3000000
  assert_equal 'container drift long-gap baseline succeeds' '0' "$COMMAND_STATUS" || return
  use_container_drift_snapshot container-drift-image-changed.json
  # #when
  run_container_drift_watch_at 3086401
  # #then
  assert_equal 'container drift long-gap comparison succeeds' '0' "$COMMAND_STATUS" || return
  assert_webhook_count 'container drift reports an image change after a watcher gap' 1 || return
  assert_webhook_event 'container drift reports the image changed during a watcher gap' alpha image 1
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
run_test test_container_drift_fake_docker_matches_the_consumed_cli_boundary
run_test test_assert_webhook_event_rejects_a_wrong_event
run_test test_assert_webhook_event_accepts_the_webhook_contract
run_test test_assert_table_cell_requires_the_expected_column
run_test test_assert_webhook_count_requires_the_exact_request_count
run_test test_assert_webhook_event_rejects_a_wrong_method
run_test test_fake_curl_records_json_request_bodies
run_test test_docker_status_shows_container_drift_columns_and_filters_services
run_test test_docker_status_skips_a_container_that_vanishes_during_inspect
run_test test_container_drift_notifies_when_restart_count_grows
run_test test_container_drift_notifies_when_image_id_changes
run_test test_container_drift_suppresses_baseline_unchanged_new_and_recreated_containers
run_test test_container_drift_notifies_about_restarts_after_a_container_is_recreated
run_test test_container_drift_retries_a_failed_webhook_without_advancing_state
run_test test_container_drift_skips_a_container_that_vanishes_during_inspect
run_test test_container_drift_retries_only_a_failed_image_event
run_test test_container_drift_retries_only_a_failed_restart_event
run_test test_container_drift_compares_a_container_that_returns_within_the_ttl
run_test test_container_drift_expires_a_container_absent_longer_than_the_ttl
run_test test_container_drift_compares_a_present_container_after_a_long_watcher_gap

if ((FAILURES)); then
  printf '%s of %s local tests failed\n' "$FAILURES" "$TESTS" >&2
  exit 1
fi

printf 'ok - %s local tests passed\n' "$TESTS"
