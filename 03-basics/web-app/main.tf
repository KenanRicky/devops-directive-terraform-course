############################################################
# TERRAFORM BACKEND (S3 + DynamoDB)
############################################################
terraform {
  backend "s3" {
    bucket         = "devops-directive-tf-state34"
    key            = "03-basics/web-app/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-rickyID"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

############################################################
# VPC + SUBNETS
############################################################
data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "default" {
  vpc_id = data.aws_vpc.default.id
}

############################################################
# SECURITY GROUPS
############################################################
resource "aws_security_group" "instances" {
  name   = "instance-security-group"
  vpc_id = data.aws_vpc.default.id
}

resource "aws_security_group_rule" "instances_http" {
  type              = "ingress"
  security_group_id = aws_security_group.instances.id
  from_port         = 8080
  to_port           = 8080
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group" "alb" {
  name   = "alb-security-group"
  vpc_id = data.aws_vpc.default.id
}

resource "aws_security_group_rule" "alb_http" {
  type              = "ingress"
  security_group_id = aws_security_group.alb.id
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "alb_egress" {
  type              = "egress"
  security_group_id = aws_security_group.alb.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

############################################################
# EC2 INSTANCES
############################################################
resource "aws_instance" "instance_1" {
  ami           = "ami-011899242bb902164"
  instance_type = "t3.micro"
  security_groups = [
    aws_security_group.instances.name
  ]

  user_data = <<-EOF
    #!/bin/bash
    echo "Hello, World 1" > index.html
    python3 -m http.server 8080 &
  EOF
}

resource "aws_instance" "instance_2" {
  ami           = "ami-011899242bb902164"
  instance_type = "t3.micro"
  security_groups = [
    aws_security_group.instances.name
  ]

  user_data = <<-EOF
    #!/bin/bash
    echo "Hello, World 2" > index.html
    python3 -m http.server 8080 &
  EOF
}

############################################################
# S3 BUCKET FOR APP STORAGE
############################################################
resource "aws_s3_bucket" "bucket" {
  bucket_prefix = "devops-directive-web-app-data"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "bucket_versioning" {
  bucket = aws_s3_bucket.bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bucket_encryption" {
  bucket = aws_s3_bucket.bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

############################################################
# LOAD BALANCER (ALB)
############################################################
resource "aws_lb" "alb" {
  name               = "web-app-lb"
  load_balancer_type = "application"
  subnets            = data.aws_subnet_ids.default.ids
  security_groups    = [aws_security_group.alb.id]
}

resource "aws_lb_target_group" "tg" {
  name     = "example-target-group"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group_attachment" "tg_attach_1" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.instance_1.id
  port             = 8080
}

resource "aws_lb_target_group_attachment" "tg_attach_2" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.instance_2.id
  port             = 8080
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

############################################################
# ROUTE53 HOSTED ZONE + A RECORD
############################################################
resource "aws_route53_zone" "primary" {
  name = "devopsdeployed.com"
}

resource "aws_route53_record" "root" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "devopsdeployed.com"
  type    = "A"

  alias {
    name                   = aws_lb.alb.dns_name
    zone_id                = aws_lb.alb.zone_id
    evaluate_target_health = true
  }
}

############################################################
# RDS (FIXED: VALID ENGINE + INSTANCE CLASS)
############################################################
resource "aws_db_instance" "db" {
  allocated_storage    = 20
  engine               = "postgres"
  engine_version       = "14.20"
  instance_class       = "db.t3.micro"
  db_name              = "mydb"
  username             = "foo"
  password             = "foobarbaz"
  skip_final_snapshot  = true
}
