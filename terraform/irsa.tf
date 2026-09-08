# -----------------------------------------------------------------------------
# IRSA — External Secrets Operator (cluster-wide)
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "external_secrets_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host_path}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host_path}:sub"
      values = [
        "system:serviceaccount:${var.external_secrets_namespace}:${var.external_secrets_service_account}"
      ]
    }
  }
}

data "aws_iam_policy_document" "external_secrets_permissions" {
  statement {
    sid    = "SecretsManagerRead"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecretVersionIds",
    ]
    resources = [
      "arn:aws:secretsmanager:${var.aws_region}:${local.account_id}:secret:zeppelin/*",
    ]
  }

  dynamic "statement" {
    for_each = local.use_cmk ? [1] : []
    content {
      sid       = "KmsDecrypt"
      effect    = "Allow"
      actions   = ["kms:Decrypt"]
      resources = [var.kms_key_arn]
      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["secretsmanager.${var.aws_region}.amazonaws.com"]
      }
    }
  }
}

resource "aws_iam_role" "external_secrets" {
  name               = "${var.name_prefix}-external-secrets"
  assume_role_policy = data.aws_iam_policy_document.external_secrets_trust.json
  description        = "IRSA for External Secrets Operator (Zeppelin secrets)"
}

resource "aws_iam_role_policy" "external_secrets" {
  name   = "${var.name_prefix}-external-secrets-sm"
  role   = aws_iam_role.external_secrets.id
  policy = data.aws_iam_policy_document.external_secrets_permissions.json
}

# -----------------------------------------------------------------------------
# IRSA — Zeppelin + Spark driver (per environment)
# Trusts:
#   - system:serviceaccount:zeppelin-<env>:zeppelin
#   - system:serviceaccount:spark-jobs-<env>:spark
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "zeppelin_trust" {
  for_each = toset(var.environments)

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host_path}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host_path}:sub"
      values = [
        "system:serviceaccount:zeppelin-${each.key}:${var.zeppelin_service_account_name}",
        "system:serviceaccount:spark-${each.key}:${var.spark_service_account_name}",
      ]
    }
  }
}

data "aws_iam_policy_document" "zeppelin_permissions" {
  for_each = toset(var.environments)

  statement {
    sid    = "NotebookBucketList"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [aws_s3_bucket.notebooks.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values = [
        "notebooks/${each.key}/*",
        "spark-history/${each.key}/*",
      ]
    }
  }

  statement {
    sid    = "NotebookAndEventLogObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]
    resources = [
      "${aws_s3_bucket.notebooks.arn}/notebooks/${each.key}/*",
      "${aws_s3_bucket.notebooks.arn}/spark-history/${each.key}/*",
    ]
  }

  dynamic "statement" {
    for_each = local.use_cmk ? [1] : []
    content {
      sid       = "KmsForS3"
      effect    = "Allow"
      actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
      resources = [var.kms_key_arn]
      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["s3.${var.aws_region}.amazonaws.com"]
      }
    }
  }
}

resource "aws_iam_role" "zeppelin" {
  for_each = toset(var.environments)

  name               = "${var.name_prefix}-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.zeppelin_trust[each.key].json
  description        = "IRSA for Zeppelin + Spark in ${each.key}"
}

resource "aws_iam_role_policy" "zeppelin" {
  for_each = toset(var.environments)

  name   = "${var.name_prefix}-${each.key}-s3"
  role   = aws_iam_role.zeppelin[each.key].id
  policy = data.aws_iam_policy_document.zeppelin_permissions[each.key].json
}
