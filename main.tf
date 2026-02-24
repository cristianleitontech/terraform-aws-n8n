terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  name_prefix = var.stack_name
  fqdn        = "${var.subdomain}.${var.root_domain}"
  tags = {
    Project     = var.stack_name
    Environment = var.environment_name
    ManagedBy   = "terraform"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_partition" "current" {}

data "aws_ami" "al2023" {
  owners      = ["amazon"]
  most_recent = true

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_vpc" "n8n" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-vpc" })
}

resource "aws_internet_gateway" "n8n" {
  vpc_id = aws_vpc.n8n.id

  tags = merge(local.tags, { Name = "${local.name_prefix}-igw" })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.n8n.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-public-subnet" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.n8n.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.n8n.id
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-public-rt" })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "n8n" {
  name        = "${local.name_prefix}-public-access"
  description = "Allow HTTP and HTTPS from the internet"
  vpc_id      = aws_vpc.n8n.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-sg" })
}

resource "aws_iam_role" "n8n" {
  name_prefix = "${local.name_prefix}-ec2-ssm-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.tags, { Name = "${local.name_prefix}-ssm-role" })
}

resource "aws_iam_role_policy_attachment" "n8n_ssm" {
  role       = aws_iam_role.n8n.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "n8n" {
  name_prefix = "${local.name_prefix}-ec2-profile-"
  role        = aws_iam_role.n8n.name
  tags        = merge(local.tags, { Name = "${local.name_prefix}-instance-profile" })
}

resource "random_password" "encryption_key" {
  length  = 32
  special = false
}

resource "aws_instance" "n8n" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.n8n.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.n8n.name

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  ebs_block_device {
    device_name           = "/dev/sdf"
    volume_size           = var.data_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = false
  }

  user_data = templatefile("${path.module}/scripts/user-data.sh.tftpl", {
    fqdn                = local.fqdn
    timezone            = var.default_timezone
    letsencrypt_email   = var.letsencrypt_email
    n8n_basic_auth_user = var.n8n_basic_auth_user
    n8n_basic_auth_pass = var.n8n_basic_auth_password
    n8n_encryption_key  = random_password.encryption_key.result
    compose_version     = var.docker_compose_version
    data_device         = "/dev/xvdf"
  })

  lifecycle {
    ignore_changes = [
      ami,
      user_data,       # Recomendado agregar esto también
      user_data_base64 # Y esto
    ]
  }

  user_data_replace_on_change = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-instance" })
}

resource "aws_eip" "n8n" {
  domain = "vpc"
  tags   = merge(local.tags, { Name = "${local.name_prefix}-eip" })
}

resource "aws_eip_association" "n8n" {
  instance_id   = aws_instance.n8n.id
  allocation_id = aws_eip.n8n.id
}

resource "aws_iam_role" "eventbridge" {
  name_prefix = "${local.name_prefix}-eventbridge-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.tags, { Name = "${local.name_prefix}-eventbridge-role" })
}

resource "aws_iam_role_policy" "eventbridge_ssm" {
  role = aws_iam_role.eventbridge.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:StartAutomationExecution"
        ]
        Resource = [
          "arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}::automation-definition/AWS-StartEC2Instance:$DEFAULT",
          "arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}::automation-definition/AWS-StopEC2Instance:$DEFAULT"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetAutomationExecution"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_cloudwatch_event_rule" "stop_instance" {
  name                = "${local.name_prefix}-stop-2am-bogota"
  schedule_expression = "cron(0 7 * * ? *)"
  description         = "Detiene la instancia ${local.name_prefix} todos los días a las 02:00 America/Bogota (07:00 UTC)"
}

resource "aws_cloudwatch_event_target" "stop_instance" {
  rule      = aws_cloudwatch_event_rule.stop_instance.name
  target_id = "StopN8nDemoInstance"
  arn       = "arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}::automation-definition/AWS-StopEC2Instance:$DEFAULT"
  role_arn  = aws_iam_role.eventbridge.arn
  input = jsonencode({
    InstanceId = [aws_instance.n8n.id]
  })
}

resource "aws_cloudwatch_event_rule" "start_instance" {
  name                = "${local.name_prefix}-start-6am-bogota"
  schedule_expression = "cron(0 11 * * ? *)"
  description         = "Inicia la instancia ${local.name_prefix} todos los días a las 06:00 America/Bogota (11:00 UTC)"
}

resource "aws_cloudwatch_event_target" "start_instance" {
  rule      = aws_cloudwatch_event_rule.start_instance.name
  target_id = "StartN8nDemoInstance"
  arn       = "arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}::automation-definition/AWS-StartEC2Instance:$DEFAULT"
  role_arn  = aws_iam_role.eventbridge.arn
  input = jsonencode({
    InstanceId = [aws_instance.n8n.id]
  })
}
