data "aws_region" "current" {}

resource "aws_ecs_cluster" "main" {
  name = "quizler"

  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE"]
}

resource "aws_cloudwatch_log_group" "server" {
  name              = "/ecs/quizler-server"
  retention_in_days = 14
}

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Pulls the image from ECR and writes logs.
resource "aws_iam_role" "task_execution" {
  name               = "quizler-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Permissions of the application itself. Empty for now: dsql:DbConnect, S3 and Bedrock
# are added together with the code that needs them.
resource "aws_iam_role" "task" {
  name               = "quizler-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

# CI registers new revisions of this family with the real image; the service ignores this one after creation.
resource "aws_ecs_task_definition" "server" {
  family                   = "quizler-server"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([{
    name      = "server"
    image     = "${aws_ecr_repository.server.repository_url}:bootstrap"
    essential = true

    portMappings = [{ containerPort = 8080, protocol = "tcp" }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.server.name
        awslogs-region        = data.aws_region.current.region
        awslogs-stream-prefix = "server"
      }
    }
  }])
}

resource "aws_ecs_service" "server" {
  name            = "quizler-server"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.server.arn
  desired_count   = 0
  launch_type     = "FARGATE"

  # One task at a time: the old task stops before the new one starts.
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = true
  }

  # CI owns the released task definition and the start and stop scripts own the desired count.
  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  depends_on = [aws_ecs_cluster_capacity_providers.main]
}
