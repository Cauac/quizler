# No NAT gateway and no private subnets: the task runs in a public subnet with a public IP.
# Only CloudFront can reach it (security group below).

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "quizler" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "quizler" }
}

resource "aws_subnet" "public" {
  count = 2

  vpc_id            = aws_vpc.main.id
  availability_zone = data.aws_availability_zones.available.names[count.index]
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)

  tags = { Name = "quizler-public-${count.index}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "quizler-public" }
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

# The CloudFront prefix list uses about 55 of the 60 default rules per security group,
# so this group must not hold any other rule.
resource "aws_security_group" "task" {
  name        = "quizler-task"
  description = "Quizler server task: port 8080 from CloudFront only"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "quizler-task" }
}

resource "aws_vpc_security_group_ingress_rule" "task_from_cloudfront" {
  security_group_id = aws_security_group.task.id
  description       = "CloudFront origin-facing"
  ip_protocol       = "tcp"
  from_port         = 8080
  to_port           = 8080
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront.id
}

# ECR, CloudWatch Logs and later DSQL and Bedrock are reached over their public endpoints.
resource "aws_vpc_security_group_egress_rule" "task_all" {
  security_group_id = aws_security_group.task.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
