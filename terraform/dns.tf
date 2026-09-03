# Custom domain for the site.
#
# Why CloudFront instead of pointing Route 53 straight at the Express Mode ALB:
# Express Mode owns its load balancer. Its HTTPS listener routes on a
# host-header rule that only matches the generated *.on.aws name, and its
# canary deployments swap the service between a primary and an alternate
# target group on every rollout. A hand-written listener rule for mvecc.dev
# would therefore point at a drained target group after each deploy, and the
# ALB certificate only covers *.on.aws.
#
# Fronting the service with CloudFront sidesteps all of that. CloudFront sends
# the *origin's* hostname in the Host header (the managed cache policy does not
# forward the viewer's), so Express Mode's own host-header rule keeps matching
# and keeps working across deployments. Every resource here is owned by this
# configuration, and static assets get edge caching for free.

locals {
  # ingress_paths[0].endpoint may be a bare hostname or a full URL; CloudFront
  # origins take a hostname only.
  origin_host = regex(
    "^(?:https?://)?([^/]+)/?$",
    aws_ecs_express_gateway_service.site.ingress_paths[0].endpoint,
  )[0]

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

# Caches by URL only and forwards no cookies, headers, or query strings, which
# is what keeps the origin Host header set to the .on.aws name.
data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.project_name} — ${var.domain_name}"
  default_root_object = "index.html"
  price_class         = var.cloudfront_price_class
  aliases             = local.site_domains

  origin {
    domain_name = local.origin_host
    origin_id   = "express-mode"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "express-mode"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = data.aws_cloudfront_cache_policy.optimized.id
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
