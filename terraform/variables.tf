variable "aws_region" {
  type        = string
  description = "AWS region for all resources (must match the EKS cluster)."
}

variable "eks_cluster_name" {
  type        = string
  description = "Existing EKS cluster name (used for OIDC / IRSA discovery)."
}

variable "environments" {
  type        = list(string)
  description = "Environments to provision (IRSA roles, S3 prefixes)."
  default     = ["dev", "staging", "prod"]

  validation {
    condition     = length(var.environments) > 0
    error_message = "At least one environment is required."
  }
}

variable "notebook_bucket_name" {
  type        = string
  description = "Globally unique S3 bucket name for Zeppelin notebooks and Spark event logs."
}

variable "name_prefix" {
  type        = string
  description = "Prefix for IAM role names (e.g. zeppelin → zeppelin-dev, zeppelin-external-secrets)."
  default     = "zeppelin"
}

variable "zeppelin_service_account_name" {
  type        = string
  description = "Kubernetes ServiceAccount name used by the Zeppelin Helm release."
  default     = "zeppelin"
}

variable "spark_service_account_name" {
  type        = string
  description = "Kubernetes ServiceAccount name for Spark drivers in spark-jobs-<env>."
  default     = "spark"
}

variable "external_secrets_namespace" {
  type        = string
  description = "Namespace where External Secrets Operator runs."
  default     = "external-secrets"
}

variable "external_secrets_service_account" {
  type        = string
  description = "ServiceAccount name for External Secrets Operator."
  default     = "external-secrets"
}

variable "kms_key_arn" {
  type        = string
  description = "Optional CMK ARN for S3. Empty = AWS-managed keys. Also used for ESO KMS decrypt if set."
  default     = ""
}

variable "tags" {
  type        = map(string)
  description = "Extra tags applied to all resources."
  default     = {}
}
