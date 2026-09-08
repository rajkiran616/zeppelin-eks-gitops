#!/usr/bin/env bash
# Same stack as kind-up.sh, targeting Docker Desktop Kubernetes.
# Notebooks use hostPath → repo local-data/notebooks (must be shared with Docker).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZEPPELIN_NS="${ZEPPELIN_NS:-zeppelin-kind}"
SPARK_NS="${SPARK_NS:-spark-kind}"
NOTEBOOKS_HOST_DIR="${NOTEBOOKS_HOST_DIR:-${ROOT}/local-data/notebooks}"
CONTEXT="${CONTEXT:-docker-desktop}"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required tool: $1" >&2
    exit 1
  }
}

need kubectl
need helm

mkdir -p "${NOTEBOOKS_HOST_DIR}"

echo "==> Using context ${CONTEXT}"
kubectl config use-context "${CONTEXT}"

echo "==> Installing Spark HA (masters + ZooKeeper + workers)"
helm upgrade --install spark "${ROOT}/charts/spark-cluster" \
  --namespace "${SPARK_NS}" \
  --create-namespace \
  -f "${ROOT}/apps/spark-cluster/values-kind.yaml" \
  --wait \
  --timeout 10m

echo "==> Installing Zeppelin (notebooks → ${NOTEBOOKS_HOST_DIR})"
helm upgrade --install zeppelin "${ROOT}/charts/zeppelin" \
  --namespace "${ZEPPELIN_NS}" \
  --create-namespace \
  -f "${ROOT}/apps/zeppelin/values-kind.yaml" \
  --set service.type=NodePort \
  --set-string service.nodePort=30080 \
  --set notebooks.volume.type=hostPath \
  --set-string notebooks.volume.hostPath="${NOTEBOOKS_HOST_DIR}" \
  --wait \
  --timeout 5m

echo "==> Waiting for rollouts"
kubectl -n "${SPARK_NS}" rollout status statefulset/spark-zookeeper --timeout=10m
kubectl -n "${SPARK_NS}" rollout status statefulset/spark-master --timeout=10m
kubectl -n "${SPARK_NS}" rollout status deploy/spark-worker --timeout=10m
kubectl -n "${ZEPPELIN_NS}" rollout status deploy/zeppelin --timeout=5m

echo ""
echo "Done."
echo "  Zeppelin UI:      http://localhost:30080  (no login / anonymous)"
echo "  Notebooks (host): ${NOTEBOOKS_HOST_DIR}"
echo "  Optional secrets: ./hack/create-local-app-secret.sh  then set appSecrets.enabled=true"
echo "  Context:          ${CONTEXT}"
echo ""
echo "Tear down:"
echo "  helm uninstall zeppelin -n ${ZEPPELIN_NS}; helm uninstall spark -n ${SPARK_NS}"
echo "  kubectl delete ns ${ZEPPELIN_NS} ${SPARK_NS}"
