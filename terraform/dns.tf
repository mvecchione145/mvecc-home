# Custom domain for the site: an ACM certificate, a CloudFront distribution in
# front of the S3 bucket in site.tf, and Route 53 aliases for each name.

locals {
  # The apex plus any extra names, e.g. www.
  site_domains = toset(concat([var.domain_name], var.domain_aliases))

  hosted_zone = coalesce(var.hosted_zone_name, var.domain_name)
}

data "aws_route53_zone" "primary" {
  name         = local.hosted_zone
  private_zone = false
}

# CloudFront only reads certificates from us-east-1, regardless of where the
# rest of the stack lives.
resource "aws_acm_certificate" "site" {
  provider = aws.us_east_1

  domain_name               = var.domain_name
  subject_alternative_names = var.domain_aliases
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  # Keyed by domain so a certificate covering several names that share one
  # validation record does not produce duplicate entries.
  for_each = {
    for option in aws_acm_certificate.site.domain_validation_options :
    option.domain_name => {
      name   = option.resource_record_name
      type   = option.resource_record_type
      record = option.resource_record_value
    }
  }

  zone_id = data.aws_route53_zone.primary.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60

  # Validation records are safe to reclaim; ACM reissues the same value.
  allow_overwrite = true
}

# Blocks until ACM sees the records above, so CloudFront never attaches a
# certificate that is still PENDING_VALIDATION.
resource "aws_acm_certificate_validation" "site" {
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.site.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# Caches by URL only and honors the Cache-Control set on each S3 object.
data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

# default_root_object only covers "/", so this maps /blog/ to
# /blog/index.html, and redirects /blog to /blog/ so relative links resolve.
resource "aws_cloudfront_function" "pretty_urls" {
  name    = "${var.project_name}-pretty-urls"
  comment = "Serve index.html for directory URLs."
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = file("${path.module}/functions/pretty-urls.js")
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.project_name} — ${var.domain_name}"
  default_root_object = "index.html"
  price_class         = var.cloudfront_price_class
  aliases             = local.site_domains

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = "s3-site"
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-site"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = data.aws_cloudfront_cache_policy.optimized.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.pretty_urls.arn
    }
  }

  # With no s3:ListBucket grant, S3 answers a missing key with 403 rather than
  # 404. Answer it with the not-found page and a real 404 status.
  custom_error_response {
    error_code            = 403
    response_code         = 404
    response_page_path    = "/404.html"
    error_caching_min_ttl = 300
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    # Referencing the validation resource, not the certificate, orders this
    # after validation completes.
    acm_certificate_arn      = aws_acm_certificate_validation.site.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# Alias records, not CNAMEs: a CNAME is illegal at the zone apex, and aliases
# are free to resolve.
resource "aws_route53_record" "site_a" {
  for_each = local.site_domains

  zone_id = data.aws_route53_zone.primary.zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "site_aaaa" {
  for_each = local.site_domains

  zone_id = data.aws_route53_zone.primary.zone_id
  name    = each.value
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}
