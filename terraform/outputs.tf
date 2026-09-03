output "site_url" {
  description = "Public HTTPS URL for the site."
  value       = try(aws_ecs_express_gateway_service.site.ingress_paths[0].endpoint, null)
}

output "ingress_paths" {
  description = "All endpoints Express Mode exposes, with their access type."
  value       = aws_ecs_express_gateway_service.site.ingress_paths
}

output "service_arn" {
  description = "ARN of the Express Mode service."
  value       = aws_ecs_express_gateway_service.site.service_arn
}

output "ecr_repository_url" {
  description = "Push target for container images."
  value       = aws_ecr_repository.site.repository_url
}

output "deployed_image" {
  description = "Exact image reference the service is running."
  value       = docker_registry_image.site.name
}

output "image_digest" {
  description = "Digest of the pushed image, for verifying what is live."
  value       = docker_registry_image.site.sha256_digest
}

output "site_domain_url" {
  description = "The custom domain the site is served from."
  value       = "https://${var.domain_name}"
}

output "all_site_domains" {
  description = "Every name pointed at the distribution."
  value       = [for name in local.site_domains : "https://${name}"]
}

output "cloudfront_domain" {
  description = "CloudFront hostname the Route 53 aliases resolve to."
  value       = aws_cloudfront_distribution.site.domain_name
}

output "certificate_arn" {
  description = "ACM certificate covering the custom domains."
  value       = aws_acm_certificate.site.arn
}
