# -----------------------------------------------------------------------------
# S3 — notebooks + Spark event logs (one bucket, env prefixes)
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "notebooks" {
  bucket = var.notebook_bucket_name
}

resource "aws_s3_bucket_public_access_block" "notebooks" {
  bucket = aws_s3_bucket.notebooks.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "notebooks" {
  bucket = aws_s3_bucket.notebooks.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "notebooks" {
  bucket = aws_s3_bucket.notebooks.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = local.use_cmk ? "aws:kms" : "AES256"
      kms_master_key_id = local.use_cmk ? var.kms_key_arn : null
    }
    bucket_key_enabled = local.use_cmk
  }
}

resource "aws_s3_bucket_ownership_controls" "notebooks" {
  bucket = aws_s3_bucket.notebooks.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Create prefix "folders" for each environment
resource "aws_s3_object" "notebook_prefixes" {
  for_each = {
    for pair in setproduct(var.environments, ["notebooks", "spark-history"]) :
    "${pair[1]}/${pair[0]}/" => {
      env    = pair[0]
      prefix = pair[1]
    }
  }

  bucket       = aws_s3_bucket.notebooks.id
  key          = each.key
  content_type = "application/x-directory"
}
