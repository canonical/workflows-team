#!/usr/bin/env bash
set -euo pipefail

: "${JUJU_MODEL:?JUJU_MODEL is required}"

GITEA_NAMESPACE="${GITEA_NAMESPACE:-gitea}"
GIT_INTEGRATOR_APP="${GIT_INTEGRATOR_APP:-gitea-action-git-integrator}"

echo "=== Removing ${GIT_INTEGRATOR_APP} ==="
juju remove-application \
    --model="${JUJU_MODEL}" \
    "${GIT_INTEGRATOR_APP}" \
    --force \
    --no-prompt

echo "=== Removing Gitea namespace ==="
if kubectl get namespace "${GITEA_NAMESPACE}" >/dev/null 2>&1; then
    kubectl delete namespace "${GITEA_NAMESPACE}" --wait=true
fi
