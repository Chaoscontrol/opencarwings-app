#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <version>" >&2
    exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

version="$1"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9]+)?$ ]]; then
    echo "Invalid app version: $version" >&2
    exit 1
fi

if [ "$(wc -l < opencarwings/.upstream_sync)" -ne 1 ] || \
    ! grep -Eq '^[0-9a-f]{40}$' opencarwings/.upstream_sync; then
    echo "opencarwings/.upstream_sync must contain one lowercase 40-character commit SHA" >&2
    exit 1
fi
upstream_commit="$(cat opencarwings/.upstream_sync)"

image="opencarwings-release-check:${version}-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-0}-$$"
image_built="false"
cleanup() {
    if [ "$image_built" = "true" ]; then
        docker image rm --force "$image" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

docker build \
    --pull \
    --platform linux/amd64 \
    --build-arg "BUILD_VERSION=${version}" \
    --build-arg "BUILD_ARCH=amd64" \
    --tag "$image" \
    opencarwings
image_built="true"

docker run --rm \
    --platform linux/amd64 \
    --entrypoint /bin/sh \
    --env "EXPECTED_UPSTREAM=${upstream_commit}" \
    "$image" \
    -ec '
        test "$(git -C /opt/opencarwings rev-parse HEAD)" = "$EXPECTED_UPSTREAM"
        test "$(tr -d "\r\n" < /tmp/upstream_sync_marker)" = "$EXPECTED_UPSTREAM"
        postgres --version | grep -Eq "PostgreSQL\) 17\."
        python3 --version
        python3 -m pip --version
        python3 -c "import pngquant, psycopg2"
        python3 -m pip check
        cd /opt/opencarwings
        cp carwings/settings.docker.py carwings/settings.py
        python3 manage.py check
        for command in bashio curl dos2unix frpc git gosu nc nginx openssl pg_ctl postgres psql python3 redis-cli redis-server timeout; do
            command -v "$command" >/dev/null
        done
    '

test "$(docker image inspect --format '{{ index .Config.Labels "io.hass.type" }}' "$image")" = "addon"
test "$(docker image inspect --format '{{ index .Config.Labels "io.hass.name" }}' "$image")" = "OpenCarwings"
test "$(docker image inspect --format '{{ index .Config.Labels "io.hass.version" }}' "$image")" = "$version"
test "$(docker image inspect --format '{{ index .Config.Labels "io.hass.arch" }}' "$image")" = "amd64"
