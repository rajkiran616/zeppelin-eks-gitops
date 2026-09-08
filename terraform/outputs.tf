output "notebook_bucket_name" {
  description = "S3 bucket for notebooks and Spark event logs (set REPLACE_ME_NOTEBOOK_BUCKET)."
  value       = aws_s3_bucket.notebooks.bucket
}

output "notebook_bucket_arn" {
  description = "ARN of the notebooks bucket."
  value       = aws_s3_bucket.notebooks.arn
}

output "external_secrets_role_arn" {
  description = "IRSA role ARN for External Secrets Operator (platform/external-secrets/values.yaml)."
  value       = aws_iam_role.external_secrets.arn
}

output "zeppelin_role_arns" {
  description = "Map of env → IRSA role ARN for Zeppelin/Spark (apps/zeppelin/values-<env>.yaml)."
  value       = { for env, role in aws_iam_role.zeppelin : env => role.arn }
}

output "oidc_provider_arn" {
  description = "EKS OIDC provider ARN used for IRSA trust policies."
  value       = local.oidc_provider_arn
}

output "gitops_placeholder_hints" {
  description = "Copy these into GitOps REPLACE_ME_* / values files after apply."
  value = {
    REPLACE_ME_NOTEBOOK_BUCKET = aws_s3_bucket.notebooks.bucket
    REPLACE_ME_ACCOUNT_ID      = local.account_id
    REPLACE_ME_REGION          = var.aws_region
    REPLACE_ME_CLUSTER_NAME    = var.eks_cluster_name
    external_secrets_role_arn  = aws_iam_role.external_secrets.arn
    zeppelin_role_arns         = { for env, role in aws_iam_role.zeppelin : env => role.arn }
  }
}

output "manual_secrets_manager_names" {
  description = "Create these secrets in AWS Console (arbitrary JSON keys → env vars). Terraform does not manage them."
  value       = [for env in var.environments : "zeppelin/${env}/app"]
}
