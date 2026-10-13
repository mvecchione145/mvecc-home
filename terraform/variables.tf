variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-2"
}

variable "project_name" {
  description = "Name prefix for the S3 bucket and CloudFront resources."
  type        = string
  default     = "mvecc-home"
}

variable "domain_name" {
  description = "Apex domain the site is served from. Must be a public hosted zone in this account."
  type        = string
  default     = "mvecc.dev"
}

variable "domain_aliases" {
  description = <<-EOT
    Extra names to serve alongside domain_name. They are added to the
    certificate, the CloudFront aliases, and Route 53. Set to [] for apex only.
  EOT
  type        = list(string)
  default     = ["www.mvecc.dev"]
}

variable "hosted_zone_name" {
  description = "Route 53 zone to write records into. Leave null to use domain_name, which is right when domain_name is the zone apex."
  type        = string
  default     = null
}

variable "cloudfront_price_class" {
  description = "CloudFront edge footprint. PriceClass_100 is North America and Europe, and the cheapest."
  type        = string
  default     = "PriceClass_100"
}
