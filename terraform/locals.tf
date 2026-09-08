data "aws_caller_identity" "current" {}

data "aws_eks_cluster" "this" {
  name = var.eks_cluster_name
}

locals {
  account_id = data.aws_caller_identity.current.account_id

  oidc_issuer_url   = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
  oidc_host_path    = replace(local.oidc_issuer_url, "https://", "")
  oidc_provider_arn = "arn:aws:iam::${local.account_id}:oidc-provider/${local.oidc_host_path}"

  use_cmk = var.kms_key_arn != ""
}
