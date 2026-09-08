# Terraform — AWS prerequisites for Zeppelin on EKS

Creates:

| Resource | Purpose |
|----------|---------|
| S3 bucket + env prefixes | Notebooks + Spark event logs |
| IRSA `*-external-secrets` | ESO → Secrets Manager read |
| IRSA `*-<env>` | Zeppelin + Spark → S3 |

Does **not** create Secrets Manager app secrets — create those in the **AWS Console** (or CLI) yourself. See [docs/secrets-convention.md](../docs/secrets-convention.md).

Does **not** create the EKS cluster, Karpenter node role, or ACM certs.

## Quick start

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars

terraform init
terraform plan
terraform apply
terraform output gitops_placeholder_hints
terraform output manual_secrets_manager_names
```

Wire role ARNs + bucket into GitOps values, then create `zeppelin/<env>/app` in Secrets Manager (JSON keys → env vars).

## IRSA ServiceAccounts

| Role | Namespace / SA |
|------|----------------|
| `${name_prefix}-external-secrets` | `external-secrets` / `external-secrets` |
| `${name_prefix}-<env>` | `zeppelin-<env>` / `zeppelin` and `spark-<env>` / `spark` |
