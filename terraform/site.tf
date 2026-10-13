# The site is a handful of static files in a private bucket. Only CloudFront
# can read it, through Origin Access Control; there is no public bucket policy
# and no S3 website endpoint.

locals {
  site_root = abspath("${path.module}/../site")
  # site/blogs/ holds post sources; blog.tf renders and uploads those.
  site_files = toset([for f in fileset(local.site_root, "**") : f if !startswith(f, "blogs/")])

  # S3 serves whatever Content-Type the object was uploaded with, so it has to
  # be set per file. Add an entry here before adding a new kind of file.
  content_types = {
    html = "text/html; charset=utf-8"
    css  = "text/css; charset=utf-8"
    js   = "text/javascript; charset=utf-8"
    svg  = "image/svg+xml"
    png  = "image/png"
    jpg  = "image/jpeg"
    ico  = "image/x-icon"
    txt  = "text/plain; charset=utf-8"
  }
}

resource "aws_s3_bucket" "site" {
  # Bucket names are global, so the account id keeps this one unique.
  bucket = "${var.project_name}-site-${data.aws_caller_identity.current.account_id}"

  # Everything in the bucket comes from ../site, so destroy can empty it.
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket = aws_s3_bucket.site.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Editing a file changes its etag, which is what makes apply re-upload it.
resource "aws_s3_object" "site" {
  for_each = local.site_files

  bucket = aws_s3_bucket.site.id
  key    = each.value
  source = "${local.site_root}/${each.value}"
  etag   = filemd5("${local.site_root}/${each.value}")

  content_type = lookup(
    local.content_types,
    lower(element(split(".", each.value), length(split(".", each.value)) - 1)),
    "application/octet-stream",
  )

  # Filenames are not content-hashed, so keep edge and browser caches short.
  # An edit is live everywhere within five minutes, with no invalidation step.
  cache_control = "public, max-age=300"
}

resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "${var.project_name}-site"
  description                       = "CloudFront access to the ${var.project_name} site bucket."
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_iam_policy_document" "site_bucket" {
  statement {
    sid       = "AllowCloudFrontRead"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    # Only this distribution, not any CloudFront distribution in any account.
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.site.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.site_bucket.json

  # The public access block rejects any policy it has not yet evaluated.
  depends_on = [aws_s3_bucket_public_access_block.site]
}
