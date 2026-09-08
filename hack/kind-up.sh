#!/usr/bin/env bash
# Bootstrap local cluster matching EKS architecture:
#   Spark HA (2 masters + ZooKeeper + workers) + Zeppelin → local notebooks dir
# No AWS / no Shiro (anonymous).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-zeppelin}"
ZEPPELIN_NS="${ZEPPELIN_NS:-zeppelin-kind}"
SPARK_NS="${SPARK_NS:-spark-kind}"
NOTEBOOKS_HOST_DIR="${NOTEBOOKS_HOST_DIR:-${ROOT}/local-data/notebooks}"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required tool: $1" >&2
    exit 1
  }
}

need kind
need kubectl
need helm

mkdir -p "${NOTEBOOKS_HOST_DIR}"

KIND_CFG="$(mktemp)"
trap 'rm -f "${KIND_CFG}"' EXIT
sed "s|NOTEBOOKS_HOST_DIR|${NOTEBOOKS_HOST_DIR}|g" \
  "${ROOT}/hack/kind-config.yaml" > "${KIND_CFG}"

echo "==> Creating Kind cluster '${CLUSTER_NAME}' (idempotent)"
if ! kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  kind create cluster --config "${KIND_CFG}"
else
  echo "    Cluster already exists; using existing context"
  echo "    (If notebooks hostPath is wrong, recreate: kind delete cluster --name ${CLUSTER_NAME})"
  kubectl cluster-info --context "kind-${CLUSTER_NAME}" >/dev/null
fi

kubectl config use-context "kind-${CLUSTER_NAME}"

echo "==> Installing Spark HA (masters + ZooKeeper + workers)"
helm upgrade --install spark "${ROOT}/charts/spark-cluster" \
  --namespace "${SPARK_NS}" \
  --create-namespace \
  -f "${ROOT}/apps/spark-cluster/values-kind.yaml" \
  --wait \
  --timeout 10m

echo "==> Installing Zeppelin (HA Spark URL; notebooks → ${NOTEBOOKS_HOST_DIR})"
helm upgrade --install zeppelin "${ROOT}/charts/zeppelin" \
  --namespace "${ZEPPELIN_NS}" \
  --create-namespace \
  -f "${ROOT}/apps/zeppelin/values-kind.yaml" \
  --set service.type=NodePort \
  --set-string service.nodePort=30080 \
  --wait \
  --timeout 5m

echo "==> Waiting for rollouts"
kubectl -n "${SPARK_NS}" rollout status statefulset/spark-zookeeper --timeout=10m
kubectl -n "${SPARK_NS}" rollout status statefulset/spark-master --timeout=10m
kubectl -n "${SPARK_NS}" rollout status deploy/spark-worker --timeout=10m
kubectl -n "${ZEPPELIN_NS}" rollout status deploy/zeppelin --timeout=5m

echo ""
echo "Done. Local architecture matches EKS (HA Spark + ZK); notebooks are on disk."
echo "  Zeppelin UI:     http://localhost:8080  (no login / anonymous)"
echo "  Notebooks (host): ${NOTEBOOKS_HOST_DIR}"
echo "  Optional secrets: ./hack/create-local-app-secret.sh  then set appSecrets.enabled=true"
echo "  Spark master:    spark://spark-master-0.spark-master-hs.${SPARK_NS}.svc.cluster.local:7077,spark-master-1.spark-master-hs.${SPARK_NS}.svc.cluster.local:7077"
echo "  Spark UI:        kubectl -n ${SPARK_NS} port-forward pod/spark-master-0 8080:8080"
echo "  Context:         kind-${CLUSTER_NAME}"
echo ""
echo "Tear down:"
echo "  kind delete cluster --name ${CLUSTER_NAME}"
