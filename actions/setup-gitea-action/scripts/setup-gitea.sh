#!/usr/bin/env bash
set -euo pipefail

: "${GITEA_NAMESPACE:?GITEA_NAMESPACE is required}"
: "${GITEA_IMAGE:?GITEA_IMAGE is required}"
: "${GITEA_USERNAME:?GITEA_USERNAME is required}"
: "${REPOSITORY_NAME:?REPOSITORY_NAME is required}"
: "${TRACKING_REF:?TRACKING_REF is required}"

ACTION_PATH="${GITHUB_ACTION_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
MANIFEST="${ACTION_PATH}/resources/gitea.yaml"

GITEA_PASSWORD="$(python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(24))
PY
)"

GITEA_TOKEN_NAME="git-integrator-$(date +%s)-${RANDOM}"
GITEA_EMAIL="${GITEA_USERNAME}@example.invalid"
GITEA_INTERNAL_BASE_URL="http://gitea.${GITEA_NAMESPACE}.svc.cluster.local:3000"
GITEA_INTERNAL_REPOSITORY_URL="${GITEA_INTERNAL_BASE_URL}/${GITEA_USERNAME}/${REPOSITORY_NAME}.git"

tmp_manifest="$(mktemp)"
port_forward_pid=""
WORKTREE=""
GIT_CREDENTIAL_FILE=""

cleanup() {
    if [[ -n "${port_forward_pid}" ]]; then
        kill "${port_forward_pid}" >/dev/null 2>&1 || true
        wait "${port_forward_pid}" >/dev/null 2>&1 || true
    fi

    rm -f "${tmp_manifest}"

    if [[ -n "${WORKTREE}" ]]; then
        rm -rf "${WORKTREE}"
    fi

    if [[ -n "${GIT_CREDENTIAL_FILE}" ]]; then
        rm -f "${GIT_CREDENTIAL_FILE}"
    fi
}
trap cleanup EXIT

export GITEA_NAMESPACE GITEA_IMAGE
envsubst < "${MANIFEST}" > "${tmp_manifest}"

echo "=== Deploying Gitea ==="

if kubectl get namespace "${GITEA_NAMESPACE}" >/dev/null 2>&1; then
    echo "::error::Namespace ${GITEA_NAMESPACE} already exists."
    exit 1
fi

kubectl create namespace "${GITEA_NAMESPACE}"

kubectl apply -f "${tmp_manifest}"


echo "=== Waiting for Gitea ==="

if ! kubectl rollout status \
    "deployment/gitea" \
    --namespace "${GITEA_NAMESPACE}" \
    --timeout=5m; then

    echo "=== Gitea deployment ==="
    kubectl get deployment gitea \
        --namespace "${GITEA_NAMESPACE}" \
        -o wide

    echo "=== Gitea pods ==="
    kubectl get pods \
        --namespace "${GITEA_NAMESPACE}" \
        -o wide

    echo "=== Gitea pod description ==="
    kubectl describe pods \
        --namespace "${GITEA_NAMESPACE}" \
        -l app=gitea

    echo "=== Gitea events ==="
    kubectl get events \
        --namespace "${GITEA_NAMESPACE}" \
        --sort-by='.lastTimestamp'

    echo "=== Gitea logs ==="
    kubectl logs \
        --namespace "${GITEA_NAMESPACE}" \
        deployment/gitea \
        --all-containers=true \
        --tail=200 || true

    exit 1
fi

LOCAL_PORT="$(python3 - <<'PY'
import socket
with socket.socket() as s:
    s.bind(("127.0.0.1", 0))
    print(s.getsockname()[1])
PY
)"

echo "=== Starting temporary Gitea port-forward ==="

kubectl port-forward \
    --namespace "${GITEA_NAMESPACE}" \
    "service/gitea" \
    "${LOCAL_PORT}:3000" >/tmp/gitea-port-forward.log 2>&1 &

port_forward_pid=$!

for _ in $(seq 1 60); do
    if curl --silent --fail \
        "http://127.0.0.1:${LOCAL_PORT}/" >/dev/null 2>&1; then
        break
    fi

    if ! kill -0 "${port_forward_pid}" >/dev/null 2>&1; then
        cat /tmp/gitea-port-forward.log >&2 || true
        echo "::error::Gitea port-forward exited unexpectedly."
        exit 1
    fi

    sleep 2
done

if ! curl --silent --fail \
    "http://127.0.0.1:${LOCAL_PORT}/" >/dev/null 2>&1; then
    cat /tmp/gitea-port-forward.log >&2 || true
    echo "::error::Gitea did not become reachable through port-forward."
    exit 1
fi

echo "=== Gitea container user ==="

kubectl exec \
    --namespace "${GITEA_NAMESPACE}" \
    deployment/gitea \
    -- \
    id

echo "=== Initializing Gitea database ==="

kubectl exec \
    --namespace "${GITEA_NAMESPACE}" \
    deployment/gitea \
    -- \
    su -s /bin/sh git -c \
    "gitea --config /data/gitea/conf/app.ini migrate"

echo "=== Creating Gitea user ==="

kubectl exec \
    --namespace "${GITEA_NAMESPACE}" \
    deployment/gitea \
    -- \
    su -s /bin/sh git -c \
    "gitea --config /data/gitea/conf/app.ini admin user create \
        --username '${GITEA_USERNAME}' \
        --password '${GITEA_PASSWORD}' \
        --email '${GITEA_EMAIL}' \
        --must-change-password=false" \
    || {
        echo "::error::Failed to create Gitea user."
        exit 1
    }

echo "=== Creating Gitea access token ==="

TOKEN_RESPONSE="$(
    curl --silent --show-error --fail \
        -X POST \
        -u "${GITEA_USERNAME}:${GITEA_PASSWORD}" \
        "http://127.0.0.1:${LOCAL_PORT}/api/v1/users/${GITEA_USERNAME}/tokens" \
        -H 'Content-Type: application/json' \
        -d "$(jq -n \
            --arg name "${GITEA_TOKEN_NAME}" \
            '{name: $name, scopes: ["all"]}'
        )"
)"

if ! GITEA_TOKEN="$(
    printf '%s' "${TOKEN_RESPONSE}" |
        jq -er '.sha1 | select(type == "string" and length > 0)'
)"; then
    echo "::error::Gitea token response did not contain a valid sha1."
    exit 1
fi

echo "::add-mask::${GITEA_TOKEN}"

echo "=== Creating Gitea repository ==="

HTTP_STATUS="$(
    curl --silent --show-error \
        -o /tmp/gitea-repo-response.json \
        -w '%{http_code}' \
        -X POST \
        -u "${GITEA_USERNAME}:${GITEA_TOKEN}" \
        "http://127.0.0.1:${LOCAL_PORT}/api/v1/user/repos" \
        -H 'Content-Type: application/json' \
        -d "$(jq -n \
            --arg name "${REPOSITORY_NAME}" \
            '{
                name: $name,
                private: true,
                auto_init: false
            }'
        )"
)"

case "${HTTP_STATUS}" in
    201)
        ;;
    409)
        echo "Repository already exists; continuing."
        ;;
    *)
        cat /tmp/gitea-repo-response.json >&2 || true
        echo "::error::Failed to create Gitea repository (HTTP ${HTTP_STATUS})."
        exit 1
        ;;
esac

echo "=== Seeding repository ==="

WORKTREE="$(mktemp -d)"

git -C "${WORKTREE}" init -q
git -C "${WORKTREE}" config user.name "Gitea CI"
git -C "${WORKTREE}" config user.email "gitea-ci@example.invalid"

cat > "${WORKTREE}/README.md" <<EOF
# ${REPOSITORY_NAME}

This repository was created by setup-gitea-action.
EOF

cat > "${WORKTREE}/TRACKING_REF" <<EOF
${TRACKING_REF}
EOF

git -C "${WORKTREE}" add README.md TRACKING_REF
git -C "${WORKTREE}" commit -q -m "Initial repository contents"
git -C "${WORKTREE}" branch -M "${TRACKING_REF}"

GIT_CREDENTIAL_FILE="$(mktemp)"
chmod 600 "${GIT_CREDENTIAL_FILE}"

printf 'protocol=http\nhost=127.0.0.1:%s\nusername=%s\npassword=%s\n\n' \
    "${LOCAL_PORT}" \
    "${GITEA_USERNAME}" \
    "${GITEA_TOKEN}" |
    git \
        -c credential.helper= \
        -c "credential.helper=store --file=${GIT_CREDENTIAL_FILE}" \
        credential approve

GIT_TERMINAL_PROMPT=0 \
git \
    -c credential.helper= \
    -c "credential.helper=store --file=${GIT_CREDENTIAL_FILE}" \
    -C "${WORKTREE}" \
    push \
    "http://127.0.0.1:${LOCAL_PORT}/${GITEA_USERNAME}/${REPOSITORY_NAME}.git" \
    "HEAD:${TRACKING_REF}"

echo "repository-url=${GITEA_INTERNAL_REPOSITORY_URL}" >> "${GITHUB_OUTPUT}"
echo "repository-name=${REPOSITORY_NAME}" >> "${GITHUB_OUTPUT}"
echo "gitea-username=${GITEA_USERNAME}" >> "${GITHUB_OUTPUT}"
echo "gitea-token=${GITEA_TOKEN}" >> "${GITHUB_OUTPUT}"

echo "Gitea repository ready: ${GITEA_INTERNAL_REPOSITORY_URL}"
