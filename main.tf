terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ====================================
# VPC y Subnets por defecto (AWS Academy)
# ====================================
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ====================================
# Security Group para el ALB
# ====================================
resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Security group for ALB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP from Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ====================================
# Security Group para las EC2 del ASG
# ====================================
resource "aws_security_group" "ec2_sg" {
  name        = "ec2-sg"
  description = "Security group for EC2 instances in ASG"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "Allow ALB to reach EC2"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ====================================
# Target Group para el ALB
# ====================================
resource "aws_lb_target_group" "tg" {
  name     = "docker-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    enabled             = true
    interval            = 30
    path                = "/"
    port                = "80"
    protocol            = "HTTP"
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# ====================================
# Application Load Balancer
# ====================================
resource "aws_lb" "alb" {
  name               = "docker-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.default.ids
}

# ====================================
# Listener del ALB
# ====================================
resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}



# ====================================
# Launch Template para las instancias EC2
# ====================================
resource "aws_launch_template" "lt" {
  name_prefix   = "docker-lt-"
  image_id      = "ami-0af7e0908d5d9420c" # 🔴 cambia si tu AMI ID es otro
  instance_type = "t2.micro"

  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  # Script que se ejecuta al iniciar la instancia
  user_data = base64encode(<<-EOF
    #!/bin/bash
    sudo systemctl start docker
    sudo docker run -d -p 80:80 ddiego24/hello-docker:v1
  EOF
  )
}


# ====================================
# Auto Scaling Group (3 - 7 instancias)
# ====================================
resource "aws_autoscaling_group" "asg" {
  name                      = "docker-asg"
  min_size                  = 3
  max_size                  = 7
  desired_capacity          = 3
  vpc_zone_identifier       = data.aws_subnets.default.ids
  target_group_arns         = [aws_lb_target_group.tg.arn]
  health_check_type         = "EC2"
  health_check_grace_period = 60

  launch_template {
    id      = aws_launch_template.lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "docker-ec2"
    propagate_at_launch = true
  }
}
