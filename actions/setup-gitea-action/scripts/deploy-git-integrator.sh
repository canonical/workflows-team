#!/usr/bin/env bash
set -euo pipefail

SECRET_FILE=""

cleanup() {
    if [[ -n "${SECRET_FILE}" ]]; then
        rm -f "${SECRET_FILE}"
    fi
}
trap cleanup EXIT

: "${JUJU_MODEL:?JUJU_MODEL is required}"
: "${GIT_INTEGRATOR_CHANNEL:?GIT_INTEGRATOR_CHANNEL is required}"
: "${REPOSITORY_URL:?REPOSITORY_URL is required}"
: "${TRACKING_REF:?TRACKING_REF is required}"
: "${REPOSITORY_PATH:?REPOSITORY_PATH is required}"
: "${GITEA_USERNAME:?GITEA_USERNAME is required}"
: "${GITEA_TOKEN:?GITEA_TOKEN is required}"
: "${GIT_INTEGRATOR_APP_NAME:?GIT_INTEGRATOR_APP_NAME is required}"

APP_NAME="${GIT_INTEGRATOR_APP_NAME}"
SECRET_NAME="gitea-action-git-integrator-credentials"

echo "=== Deploying ${APP_NAME} ==="

juju deploy \
    git-integrator \
    "${APP_NAME}" \
    --channel="${GIT_INTEGRATOR_CHANNEL}" \
    --model="${JUJU_MODEL}"

echo "=== Waiting for application registration ==="

juju wait-for application "${APP_NAME}" \
    --model="${JUJU_MODEL}" \
    --query='life=="alive"' \
    --timeout=2m

echo "=== Creating Juju secret ==="

JUJU_SNAP_COMMON="${HOME}/snap/juju/common"
mkdir -p "${JUJU_SNAP_COMMON}"

SECRET_FILE="$(mktemp "${JUJU_SNAP_COMMON}/secret.XXXXXX")"
chmod 600 "${SECRET_FILE}"

printf 'credentials-personal-access-token: %s\n' \
    "${GITEA_TOKEN}" > "${SECRET_FILE}"

SECRET_URI="$(
    juju add-secret \
        --model="${JUJU_MODEL}" \
        "${SECRET_NAME}" \
        --file="${SECRET_FILE}" |
        awk '/^secret:/ {print $1}'
)"

if [[ -z "${SECRET_URI}" ]]; then
    echo "::error::Failed to extract secret URI from Juju output."
    exit 1
fi

# diagnosing secret-grant failures
echo "=== Current Juju model ==="
juju show-model "${JUJU_MODEL}"

echo "=== Current Juju applications ==="
juju status --model="${JUJU_MODEL}" --format=tabular

echo "=== Granting Juju secret ==="
juju grant-secret \
    --model="${JUJU_MODEL}" \
    "${SECRET_URI}" \
    "${APP_NAME}"

echo "=== Configuring ${APP_NAME} ==="
juju config \
    --model="${JUJU_MODEL}" \
    "${APP_NAME}" \
    authentication_method="credentials" \
    credentials_personal_access_token_secret="${SECRET_URI}" \
    credentials_username="${GITEA_USERNAME}" \
    repository_url="${REPOSITORY_URL}" \
    path="${REPOSITORY_PATH}" \
    tracking_ref="${TRACKING_REF}"

echo "=== Waiting for ${APP_NAME} ==="

if ! juju wait-for application \
    "${APP_NAME}" \
    --model="${JUJU_MODEL}" \
    --timeout=10m; then

    echo "::error::${APP_NAME} failed to reach its goal state."

    echo "=== git-integrator diagnostics ==="

    echo "--- Application status ---"
    juju status \
        --model="${JUJU_MODEL}" \
        --format=tabular

    echo "--- Unit details ---"
    juju show-unit \
        --model="${JUJU_MODEL}" \
        "${APP_NAME}/0"

    echo "--- Recent charm logs ---"
    juju debug-log \
        --model="${JUJU_MODEL}" \
        --include "${APP_NAME}/0" \
        --replay \
        --lines 200

    exit 1
fi

echo "${APP_NAME} is ready."

echo "git-integrator-app=${APP_NAME}" >> "${GITHUB_OUTPUT}"
