resource "aws_dsql_cluster" "main" {
  deletion_protection_enabled = true

  tags = { Name = "quizler-db" }
}

# Lets the owner connect from a laptop with an admin token (aws dsql generate-db-connect-admin-auth-token)
# to create the application database role and its AWS IAM GRANT.
data "aws_iam_user" "owner" {
  user_name = "quizler-terraform"
}

resource "aws_iam_user_policy" "owner_dsql_admin" {
  name = "dsql-admin"
  user = data.aws_iam_user.owner.user_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "dsql:DbConnectAdmin"
      Resource = aws_dsql_cluster.main.arn
    }]
  })
}

output "dsql_endpoint" {
  value = "${aws_dsql_cluster.main.identifier}.dsql.eu-north-1.on.aws"
}
