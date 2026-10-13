#!/usr/bin/env bash
# Runs on the laptop.

set -u

if (($# == 0)); then
    printf 'Usage: %s <service> [<service>...]\n' "$0" >&2
    exit 2
fi

if [[ $(git branch --show-current) != main ]]; then
    printf 'ship must run from the main branch.\n' >&2
    exit 1
fi

if [[ -n $(git status --porcelain) ]]; then
    printf 'ship requires a clean local tree; it is dirty.\n' >&2
    exit 1
fi

for service in "$@"; do
    if [[ ! -f "services/$service/docker-compose.yml" ]]; then
        printf 'Service %s has no services/%s/docker-compose.yml.\n' "$service" "$service" >&2
        exit 1
    fi
done

git push origin main
local_head=$(git rev-parse HEAD)
services=$(printf ' %q' "$@")

remote_command=$(cat <<EOF
dirty=\$(git status --porcelain)
if [[ -n \$dirty ]]; then
    printf '%s\\n' 'Server tree is dirty:' >&2
    printf '%s\\n' "\$dirty" >&2
    printf '%s\\n' 'Reset it manually: cd /opt/homelab && git reset --hard && git clean -fd' >&2
    exit 1
fi

git pull --ff-only || exit \$?
server_head=\$(git rev-parse HEAD)
printf 'Server HEAD: %s\\n' "\$server_head"
if [[ \$server_head != $local_head ]]; then
    printf 'Server HEAD does not match local HEAD %s.\\n' '$local_head' >&2
    exit 1
fi

deploy_status=0
./scripts/docker/deploy.sh$services || deploy_status=\$?
./scripts/docker/status.sh$services
status_status=\$?
if ((deploy_status != 0)); then
    exit \$deploy_status
fi
exit \$status_status
EOF
)

"$(dirname "$0")/hl" "$remote_command"
