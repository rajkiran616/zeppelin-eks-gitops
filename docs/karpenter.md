# Karpenter NodePools / EC2NodeClasses for Zeppelin + Spark

## Design (AWS Data on EKS aligned)

| Tier | EC2NodeClass | NodePools | Capacity | Instance guidance |
|------|--------------|-----------|----------|-------------------|
| Non-prod | `zeppelin-nonprod` | `zeppelin-nonprod`, `spark-nonprod` | Zeppelin On-Demand; Spark Spot+OD | Small: `large`–`2xlarge`, gen>4, Nitro |
| Prod | `zeppelin-prod` | `zeppelin-prod`, `spark-driver-prod`, `spark-executor-prod` (+ OD fallback) | Zeppelin+drivers On-Demand; executors Spot | Current-gen `m7i`/`m6i`/`r7i`/`r6i`/`c7i`/`c6i`, `2xlarge`–`8xlarge` |

**Why split in prod:** Spot reclaim on a Spark **driver** fails the whole job. Executors tolerate Spot with diversification across families/AZs. Notebook UI stays On-Demand so Zeppelin is not interrupted by Spot.

## Labels & taints (workloads must match)

| Workload | `nodeSelector` | Taint / toleration `workload.apache.org/dedicated=` |
|----------|----------------|------------------------------------------------------|
| Zeppelin | `workload.apache.org/component=zeppelin` | `zeppelin` |
| Non-prod Spark | `…=spark` | `spark` |
| Prod driver | `…=spark-driver` | `spark-driver` |
| Prod executor | `…=spark-executor` | `spark-executor` |

Helm values under `apps/zeppelin/values-*.yaml` already set these for Zeppelin pods and `SPARK_SUBMIT_OPTIONS`.

## Placeholders

| Key | Example |
|-----|---------|
| `REPLACE_ME_KARPENTER_NODE_ROLE` | IAM role name Karpenter uses for nodes |
| `REPLACE_ME_CLUSTER_NAME` | Tag value on subnets/SGs (`karpenter.sh/discovery`) |
| `REPLACE_ME_AZ_A/B/C` | e.g. `us-east-1a`, `us-east-1b`, `us-east-1c` |

## Apply path

Synced by Argo CD ApplicationSets:

- Nonprod NodePools: `zeppelin-env-dev` → Application `dev-karpenter`
- Prod NodePools: `zeppelin-env-prod` → Application `prod-karpenter`

(Staging uses the same nonprod NodePools; it does not own a Karpenter Application.)

```bash
kubectl get ec2nodeclass
kubectl get nodepool
kubectl get node -L workload.apache.org/component,karpenter.sh/nodepool
```

## Assumptions

- Karpenter v1 CRDs installed on the cluster
- Subnets/security groups tagged `karpenter.sh/discovery=REPLACE_ME_CLUSTER_NAME`
- Node IAM role allows ECR pull + CloudWatch as needed
- Zeppelin Spark uses **cluster** deploy-mode so driver pods schedule onto `spark-driver-*` / `spark-nonprod` pools (executors onto executor / shared spark pools)
