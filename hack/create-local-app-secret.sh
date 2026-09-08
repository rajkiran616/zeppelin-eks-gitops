#!/usr/bin/env bash
# Create/update a local K8s Secret for Zeppelin app credentials (not login/Shiro).
# Keys become env vars when apps/zeppelin values set appSecrets.envFrom: true.
#
#   # from literals:
#   ./hack/create-local-app-secret.sh KEY1=val1 KEY2=val2
#   # from env file:
#   ./hack/create-local-app-secret.sh --from-env-file local-data/app.env
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZEPPELIN_NS="${ZEPPELIN_NS:-zeppelin-kind}"
SECRET_NAME="${SECRET_NAME:-zeppelin-app}"

kubectl get ns "${ZEPPELIN_NS}" >/dev/null 2>&1 || kubectl create namespace "${ZEPPELIN_NS}"

if [[ $# -eq 0 ]]; then
  ENV_FILE="${ROOT}/local-data/app.env"
  if [[ ! -f "${ENV_FILE}" ]]; then
    mkdir -p "${ROOT}/local-data"
    cat > "${ENV_FILE}" <<'EOF'
# Local app secret keys (gitignored). Example:
# MY_API_TOKEN=replace-me
EOF
    echo "Created ${ENV_FILE} — add KEY=value lines, then re-run:"
    echo "  $0 --from-env-file ${ENV_FILE}"
    exit 0
  fi
  set -- --from-env-file "${ENV_FILE}"
fi

args=()
if [[ "${1:-}" == "--from-env-file" ]]; then
  args+=(--from-env-file "${2:?path required}")
else
  for kv in "$@"; do
    args+=(--from-literal="${kv}")
  done
fi

kubectl -n "${ZEPPELIN_NS}" create secret generic "${SECRET_NAME}" \
  "${args[@]}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Secret ${ZEPPELIN_NS}/${SECRET_NAME} ready."
echo "Enable in values: appSecrets.enabled=true, source=existing, secretName=${SECRET_NAME}"
