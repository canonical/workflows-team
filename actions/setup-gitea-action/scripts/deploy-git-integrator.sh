#!/usr/bin/env bash
set -euo pipefail

: "${JUJU_MODEL:?JUJU_MODEL is required}"
: "${GIT_INTEGRATOR_CHANNEL:?GIT_INTEGRATOR_CHANNEL is required}"
: "${REPOSITORY_URL:?REPOSITORY_URL is required}"
: "${TRACKING_REF:?TRACKING_REF is required}"
: "${REPOSITORY_PATH:?REPOSITORY_PATH is required}"
: "${GITEA_USERNAME:?GITEA_USERNAME is required}"
: "${GITEA_TOKEN:?GITEA_TOKEN is required}"

APP_NAME="git-integrator"
SECRET_NAME="git-integrator-credentials"

echo "=== Deploying ${APP_NAME} ==="

if ! juju status \
    --model="${JUJU_MODEL}" \
    --format=json |
    jq -e --arg app "${APP_NAME}" \
    '.applications | has($app)' >/dev/null; then

    echo "Application ${APP_NAME} not found. Deploying..."

    juju deploy \
        "${APP_NAME}" \
        --channel="${GIT_INTEGRATOR_CHANNEL}" \
        --model="${JUJU_MODEL}"
else
    echo "Application ${APP_NAME} already exists."
fi

echo "=== Waiting for application registration ==="

for _ in $(seq 1 60); do
    if juju status \
        --model="${JUJU_MODEL}" \
        --format=json |
        jq -e --arg app "${APP_NAME}" \
        '.applications | has($app)' >/dev/null 2>&1; then
        break
    fi

    sleep 2
done

if ! juju status \
    --model="${JUJU_MODEL}" \
    --format=json |
    jq -e --arg app "${APP_NAME}" \
    '.applications | has($app)' >/dev/null 2>&1; then

    juju status --model="${JUJU_MODEL}"

    echo "::error::Application ${APP_NAME} was not registered in the model."
    exit 1
fi

echo "=== Creating Juju secret ==="
SECRET_URI="$(
    juju add-secret \
        --model="${JUJU_MODEL}" \
        "${SECRET_NAME}" \
        "credentials-personal-access-token=${GITEA_TOKEN}" \
        | awk '/^secret:/ {print $1}'
)"

if [[ -z "${SECRET_URI}" ]]; then
    echo "::error::Failed to create Juju secret."
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
        --format=yaml

    echo "--- Unit details ---"
    juju show-unit \
        --model="${JUJU_MODEL}" \
        git-integrator/0

    echo "--- Recent charm logs ---"
    juju debug-log \
        --model="${JUJU_MODEL}" \
        --include git-integrator/0 \
        --replay \
        --lines 100

    exit 1
fi

echo "git-integrator is ready."

echo "git-integrator-app=${APP_NAME}" >> "${GITHUB_OUTPUT}"
