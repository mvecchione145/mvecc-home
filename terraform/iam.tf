# Express Mode needs two roles: one ECS assumes to pull the image and ship logs,
# and one it assumes to stand up the load balancer, scaling, and networking.

data "aws_iam_policy_document" "task_execution_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_execution" {
  name               = "${var.project_name}-task-execution"
  assume_role_policy = data.aws_iam_policy_document.task_execution_assume.json
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "infrastructure_assume" {
  statement {
    sid     = "AllowAccessInfrastructureForECSExpressServices"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "infrastructure" {
  name               = "${var.project_name}-express-infrastructure"
  assume_role_policy = data.aws_iam_policy_document.infrastructure_assume.json
}

resource "aws_iam_role_policy_attachment" "infrastructure" {
  role       = aws_iam_role.infrastructure.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSInfrastructureRoleforExpressGatewayServices"
}

# Service-linked roles.
#
# Express Mode leans on three AWS-managed service-linked roles. Each service
# creates its own on first use, but creation and the very next AssumeRole are
# not atomic: the first CreateExpressGatewayService in a fresh account fails
# with "Unable to assume the service linked role" because IAM has not
# propagated the role it just made. Creating them here, ahead of the service
# and behind the propagation wait, makes the first apply deterministic instead
# of a race that happens to need a second run.

resource "aws_iam_service_linked_role" "elasticloadbalancing" {
  aws_service_name = "elasticloadbalancing.amazonaws.com"
  description      = "Lets Express Mode manage its Application Load Balancer."
}

resource "aws_iam_service_linked_role" "application_autoscaling" {
  aws_service_name = "ecs.application-autoscaling.amazonaws.com"
  description      = "Lets Express Mode scale the service on CPU utilization."
}

# The ECS role, arn:...:role/aws-service-role/ecs.amazonaws.com/AWSServiceRoleForECS,
# is deliberately not declared here: it already exists in this account, and
# declaring an existing service-linked role fails with EntityAlreadyExists.
# Set create_ecs_service_linked_role = true when deploying into a fresh account
# that has never run ECS.
resource "aws_iam_service_linked_role" "ecs" {
  count = var.create_ecs_service_linked_role ? 1 : 0

  aws_service_name = "ecs.amazonaws.com"
  description      = "Lets ECS manage the cluster on your behalf."
}
