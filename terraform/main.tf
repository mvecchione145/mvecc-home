# IAM roles are eventually consistent. Without a short pause, the first apply
# can fail with "Unable to assume the service linked role" before the freshly
# created roles have propagated.
resource "time_sleep" "iam_propagation" {
  depends_on = [
    aws_iam_role_policy_attachment.task_execution,
    aws_iam_role_policy_attachment.infrastructure,
    aws_iam_service_linked_role.elasticloadbalancing,
    aws_iam_service_linked_role.application_autoscaling,
    aws_iam_service_linked_role.ecs,
  ]

  # depends_on alone would not re-run the wait for roles added after this
  # resource was first created. Keying the triggers on the role ARNs replaces
  # the timer whenever the set of roles changes, so a newly created role always
  # gets its propagation window.
  triggers = {
    task_execution          = aws_iam_role.task_execution.arn
    infrastructure          = aws_iam_role.infrastructure.arn
    elasticloadbalancing    = aws_iam_service_linked_role.elasticloadbalancing.arn
    application_autoscaling = aws_iam_service_linked_role.application_autoscaling.arn
  }

  create_duration = "60s"
}

# Express Mode provisions the Fargate service, an internet-facing ALB with
# managed SSL/TLS, auto scaling, CloudWatch logging, and an
# https://<service>.ecs.<region>.on.aws URL — all from this one resource.
#
# `network_configuration` is intentionally omitted, which puts the service in
# the account's default VPC and public subnets. See the README prerequisite.
resource "aws_ecs_express_gateway_service" "site" {
  service_name = var.project_name

  execution_role_arn      = aws_iam_role.task_execution.arn
  infrastructure_role_arn = aws_iam_role.infrastructure.arn

  health_check_path = var.health_check_path

  # Null means "let AWS pick the default" (1 vCPU / 2 GB).
  cpu    = var.cpu
  memory = var.memory

  primary_container {
    # Depends on the push, so the image is in ECR before the service starts.
    image          = docker_registry_image.site.name
    container_port = var.container_port
  }

  wait_for_steady_state = true

  depends_on = [time_sleep.iam_propagation]
}
