locals {
  # The repository issues immutable subject claims ("repo:<owner>@<owner id>/<repo>@<repo id>:...").
  # Check with: gh api repos/Cauac/quizler/actions/oidc/customization/sub
  # and the IDs with: gh api repos/Cauac/quizler --jq '.id, .owner.id'
  github_owner_id = 2319804
  github_repo_id  = 1406286552
  github_subject  = "repo:Cauac@${local.github_owner_id}/quizler@${local.github_repo_id}"
}

data "aws_caller_identity" "current" {}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

# Used by .github/workflows/deploy.yml and stop.yml. Trusted only for the main branch
# (scheduled workflows run on main as well), identified by the immutable owner and repository IDs.
resource "aws_iam_role" "deploy" {
  name = "quizler-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "${local.github_subject}:ref:refs/heads/main"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "deploy" {
  name = "deploy"
  role = aws_iam_role.deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrLogin"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "EcrPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:DescribeImages", # re-runs skip the push when the tag exists (tags are immutable)
        ]
        Resource = aws_ecr_repository.server.arn
      },
      {
        # These two actions do not support resource-level permissions.
        Sid      = "TaskDefinitions"
        Effect   = "Allow"
        Action   = ["ecs:RegisterTaskDefinition", "ecs:DescribeTaskDefinition"]
        Resource = "*"
      },
      {
        Sid      = "Service"
        Effect   = "Allow"
        Action   = ["ecs:UpdateService", "ecs:DescribeServices"]
        Resource = aws_ecs_service.server.id
      },
      {
        Sid      = "PassTaskRoles"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = [aws_iam_role.task.arn, aws_iam_role.task_execution.arn]
        Condition = {
          StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" }
        }
      },
      {
        # For sync-origin-dns.sh
        Sid      = "ListClusterTasks"
        Effect   = "Allow"
        Action   = "ecs:ListTasks"
        Resource = "*"
        Condition = {
          ArnEquals = { "ecs:cluster" = aws_ecs_cluster.main.arn }
        }
      },
      {
        Sid      = "DescribeClusterTasks"
        Effect   = "Allow"
        Action   = "ecs:DescribeTasks"
        Resource = "arn:aws:ecs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:task/${aws_ecs_cluster.main.name}/*"
      },
      {
        Sid      = "DescribeNetworkInterfaces"
        Effect   = "Allow"
        Action   = "ec2:DescribeNetworkInterfaces"
        Resource = "*"
      },
      {
        # Only the origin record may be changed: not the apex, www or the ACM validation records.
        Sid      = "OriginRecord"
        Effect   = "Allow"
        Action   = "route53:ChangeResourceRecordSets"
        Resource = aws_route53_zone.main.arn
        Condition = {
          "ForAllValues:StringEquals" = {
            "route53:ChangeResourceRecordSetsNormalizedRecordNames" = ["origin.quizler.app"]
            "route53:ChangeResourceRecordSetsRecordTypes"           = ["A"]
            "route53:ChangeResourceRecordSetsActions"               = ["UPSERT"]
          }
        }
      },
      {
        # Lets the scripts find the zone ID. Read-only; cannot be limited to one zone.
        Sid      = "FindHostedZone"
        Effect   = "Allow"
        Action   = "route53:ListHostedZonesByName"
        Resource = "*"
      },
      {
        Sid      = "OriginRecordChange"
        Effect   = "Allow"
        Action   = "route53:GetChange"
        Resource = "arn:aws:route53:::change/*"
      },
    ]
  })
}

output "deploy_role_arn" {
  description = "Value of the AWS_DEPLOY_ROLE_ARN repository variable in GitHub"
  value       = aws_iam_role.deploy.arn
}
