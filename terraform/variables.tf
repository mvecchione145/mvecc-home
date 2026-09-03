variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-2"
}

variable "project_name" {
  description = "Name prefix used for the ECR repo, IAM roles, and the service."
  type        = string
  default     = "mvecc-home"
}

variable "image_tag" {
  description = <<-EOT
    Optional override for the image tag. Leave null and Terraform tags the
    image with a hash of the site sources, so editing the site is what triggers
    a new rollout. Set it to an older tag to roll back.
  EOT
  type        = string
  default     = null
}

variable "container_port" {
  description = "Port the container listens on. Must match the nginx.conf listen directive."
  type        = number
  default     = 80
}

variable "health_check_path" {
  description = "Path the Express Mode load balancer probes. Served by nginx.conf."
  type        = string
  default     = "/healthz"
}

variable "cpu" {
  description = "vCPU for the task, as a string (e.g. \"1\"). Leave null to take the AWS default of 1 vCPU."
  type        = string
  default     = null
}

variable "memory" {
  description = "Memory in GB for the task, as a string (e.g. \"2\"). Leave null to take the AWS default of 2 GB."
  type        = string
  default     = null
}

variable "image_retention_count" {
  description = "How many tagged images to keep in ECR before expiring the oldest."
  type        = number
  default     = 15
}

variable "ecr_force_delete" {
  description = "Allow `terraform destroy` to remove the ECR repository along with the images Terraform pushed into it."
  type        = bool
  default     = true
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

variable "docker_host" {
  description = <<-EOT
    Docker daemon endpoint for the build. Leave null to use the Docker Desktop
    socket at ~/.docker/run/docker.sock. Set it for a different runtime, e.g.
    "unix:///var/run/docker.sock" on Linux. `docker context ls` prints the
    endpoint your CLI uses.
  EOT
  type        = string
  default     = null
}

variable "create_ecs_service_linked_role" {
  description = <<-EOT
    Create the AWSServiceRoleForECS service-linked role. Leave false when the
    account already has one — declaring an existing service-linked role fails
    with EntityAlreadyExists. Set it true only for an account that has never
    run ECS. `aws iam get-role --role-name AWSServiceRoleForECS` tells you which.
  EOT
  type        = bool
  default     = false
}
