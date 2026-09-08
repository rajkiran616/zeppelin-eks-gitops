# Bootstrap guide — one-time setup on an existing EKS cluster

This repository assumes:

- An EKS cluster with an IAM OIDC provider (IRSA)
- Argo CD installed in the `argocd` namespace
- AWS Load Balancer Controller (for ALB Ingress)
- Permissions to create IAM roles and Secrets Manager secrets

## Preferred: Terraform (S3 + IRSA) + Secrets in AWS Console

Use [`terraform/`](../terraform/) for:

- Notebooks / Spark event-log **S3** bucket + prefixes
- **IRSA** roles for External Secrets and per-env Zeppelin/Spark

**App secrets:** create `zeppelin/<env>/app` yourself in the **AWS Secrets Manager console** (arbitrary JSON keys → env vars). Terraform does not manage them — see [secrets-convention.md](secrets-convention.md). Zeppelin UI has no Shiro (anonymous).

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # edit cluster name, bucket, region
terraform init && terraform apply
terraform output gitops_placeholder_hints
terraform output manual_secrets_manager_names
```

Paste role ARNs and the bucket name into GitOps values (`REPLACE_ME_*`).

The sections below remain as a **manual CLI alternative** if you are not using Terraform.

## 1. Replace placeholders

Search the repo for `REPLACE_ME_` and set:

| Placeholder | Meaning |
|-------------|---------|
| `REPLACE_ME_GITOPS_REPO_URL` | HTTPS or SSH URL of this GitOps repo |
| `REPLACE_ME_ACCOUNT_ID` | AWS account ID |
| `REPLACE_ME_REGION` | e.g. `us-east-1` |
| `REPLACE_ME_OIDC_ID` | EKS OIDC issuer ID (last path segment) |
| `REPLACE_ME_NOTEBOOK_BUCKET` | S3 bucket for notebooks + Spark event logs |
| `REPLACE_ME_CERT_ID` | ACM certificate ID for Ingress |
| `REPLACE_ME_KMS_KEY_ID` | Optional CMK used by Secrets Manager |
| `REPLACE_ME_ENV` | `dev`, `staging`, or `prod` (in IAM templates) |

Also update Ingress hosts under `apps/zeppelin/values-*.yaml`.

## 2. Create S3 prefixes

```bash
aws s3 mb s3://REPLACE_ME_NOTEBOOK_BUCKET --region REPLACE_ME_REGION
aws s3api put-object --bucket REPLACE_ME_NOTEBOOK_BUCKET --key notebooks/dev/
aws s3api put-object --bucket REPLACE_ME_NOTEBOOK_BUCKET --key notebooks/staging/
aws s3api put-object --bucket REPLACE_ME_NOTEBOOK_BUCKET --key notebooks/prod/
aws s3api put-object --bucket REPLACE_ME_NOTEBOOK_BUCKET --key spark-history/dev/
aws s3api put-object --bucket REPLACE_ME_NOTEBOOK_BUCKET --key spark-history/staging/
aws s3api put-object --bucket REPLACE_ME_NOTEBOOK_BUCKET --key spark-history/prod/
```

## 3. Create Secrets Manager secrets (AWS Console)

Create one secret per environment named `zeppelin/<env>/app`.

In the Console, set secret type to **Other type of secret** → key/value pairs (any keys you need as env vars).

Or CLI:

```bash
# app-dev.json → { "MY_API_TOKEN": "…", "JDBC_PASSWORD": "…" }
aws secretsmanager create-secret \
  --name zeppelin/dev/app \
  --secret-string file://app-dev.json \
  --region REPLACE_ME_REGION
```

| Env | Secret id |
|-----|-----------|
| dev | `zeppelin/dev/app` |
| staging | `zeppelin/staging/app` |
| prod | `zeppelin/prod/app` |

## 4. Create IRSA roles

For each role, use `iam/irsa-trust-policy.json` as the trust policy (set namespace + SA):

| IAM role name | Namespace | ServiceAccount | Permission policy |
|---------------|-----------|----------------|-------------------|
| `external-secrets` | `external-secrets` | `external-secrets` | `iam/irsa-external-secrets.json` |
| `zeppelin-dev` | `zeppelin-dev` | `zeppelin` (release SA) | `iam/irsa-zeppelin.json` (`REPLACE_ME_ENV=dev`) |
| `zeppelin-staging` | `zeppelin-staging` | `zeppelin` | `iam/irsa-zeppelin.json` |
| `zeppelin-prod` | `zeppelin-prod` | `zeppelin` | `iam/irsa-zeppelin.json` |

The Spark SA `spark` in `spark-<env>` reuses the same Zeppelin IRSA role ARN (annotated in the chart) so notebooks and drivers share S3 access. Optionally create a dedicated role from `iam/irsa-spark.json` and point the Spark SA annotation at it.

```bash
# Illustrative — adapt to your IAM tooling / Terraform
aws iam create-role \
  --role-name external-secrets \
  --assume-role-policy-document file://iam/irsa-trust-policy.json

aws iam put-role-policy \
  --role-name external-secrets \
  --policy-name external-secrets-sm \
  --policy-document file://iam/irsa-external-secrets.json
```

Update role ARNs in:

- `platform/external-secrets/values.yaml`
- `apps/zeppelin/values-*.yaml`
- `platform/cluster-secret-store/clustersecretstore.yaml` (region)

## 4b. Karpenter discovery tags + AZs

Tag private subnets and the node security group:

```bash
# karpenter.sh/discovery = your EKS cluster name
```

Edit `platform/karpenter/**`:

- `REPLACE_ME_KARPENTER_NODE_ROLE`
- `REPLACE_ME_CLUSTER_NAME`
- `REPLACE_ME_AZ_A` / `_B` / `_C` (prod NodePools)

See [docs/karpenter.md](karpenter.md) for NodePool sizing rationale.

## 5. Push this repo and register with Argo CD

```bash
git add .
git commit -m "Initial Zeppelin EKS GitOps"
git push -u origin main

# If Argo CD needs a private repo credential:
# argocd repo add REPLACE_ME_GITOPS_REPO_URL --ssh-private-key-path ~/.ssh/id_rsa
```

## 6. Apply AppProject + ApplicationSets

```bash
kubectl apply -f argocd/projects/zeppelin.yaml
kubectl apply -f argocd/applicationsets/shared-platform-appset.yaml
kubectl apply -f argocd/applicationsets/env-dev-appset.yaml
kubectl apply -f argocd/applicationsets/env-staging-appset.yaml
kubectl apply -f argocd/applicationsets/env-prod-appset.yaml
```

Each environment has its **own** ApplicationSet (`zeppelin-env-dev` / `staging` / `prod`), so you can sync, pause, or change one env without regenerating the others.

New to ApplicationSets / Go templates? Read [argo-applicationsets.md](argo-applicationsets.md) — every field in the YAML is also commented in place under `argocd/applicationsets/`.

Sync order (via annotations / waves):

- Shared: External Secrets → ClusterSecretStore  
- Per env: Karpenter NodePools (dev owns nonprod; prod owns prod) → Spark Standalone → Zeppelin  

## 7. Verify

```bash
kubectl get applications -n argocd
kubectl get pods -n external-secrets
kubectl get pods -n spark-dev
kubectl get pods -n zeppelin-dev
kubectl get externalsecret -n zeppelin-dev
kubectl get ingress -n zeppelin-dev
```

Open the Ingress hostname for the environment. Run a Spark paragraph in Zeppelin, or port-forward an active master UI (`pod/spark-master-0`).

## Optional follow-ups (out of scope for v1)

- Spark History Server pointing at `s3a://…/spark-history/<env>/`
- Karpenter NodePools for Spark executors
- YuniKorn gang scheduling
- Prometheus ServiceMonitors
