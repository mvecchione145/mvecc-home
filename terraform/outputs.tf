output "site_domain_url" {
  description = "The custom domain the site is served from."
  value       = "https://${var.domain_name}"
}

output "all_site_domains" {
  description = "Every name pointed at the distribution."
  value       = [for name in local.site_domains : "https://${name}"]
}

output "cloudfront_domain" {
  description = "CloudFront hostname the Route 53 aliases resolve to. Works before DNS does."
  value       = "https://${aws_cloudfront_distribution.site.domain_name}"
}

output "bucket_name" {
  description = "S3 bucket holding the site files."
  value       = aws_s3_bucket.site.id
}

output "certificate_arn" {
  description = "ACM certificate covering the custom domains."
  value       = aws_acm_certificate.site.arn
}
