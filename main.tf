terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls",
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local",
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-2"
}

resource "aws_vpc" "main" {
  cidr_block = "10.10.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "minimal-ec2-arm-vpc"
  }
}

locals {
  azs = ["ap-northeast-2a", "ap-northeast-2c"]
  nat_az = "ap-northeast-2a"

  public_subnets = {
    "ap-northeast-2a" = "10.10.1.0/24"
    "ap-northeast-2c" = "10.10.2.0/24"
  }

  private_subnets = {
    "ap-northeast-2a" = "10.10.101.0/24"
    "ap-northeast-2c" = "10.10.102.0/24"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "minimal-ec2-arm-igw"
  }
}

resource "aws_subnet" "public" {
  for_each                = local.public_subnets
  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = true
  tags = {
    Name = "public-${each.key}"
    Tier = "public"
  }
}

resource "aws_subnet" "private" {
  for_each                = local.private_subnets
  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = false
  tags = {
    Name = "private-${each.key}"
    Tier = "private"
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags = {
    Name = "nat-eip"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[local.nat_az].id
  depends_on    = [aws_internet_gateway.igw]
  tags = {
    Name = "nat-${local.nat_az}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "rt-public"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = { Name = "rt-private-shared" }
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

data "aws_ami" "ubuntu_2404_arm64" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

resource "tls_private_key" "ssh" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "minimal-ec2-arm" {
  key_name   = "minimal-ec2-arm-ssh"
  public_key = tls_private_key.ssh.public_key_openssh
}

resource "local_sensitive_file" "private_key" {
  filename = "${path.module}/minimal-ec2-arm-ssh"
  content  = tls_private_key.ssh.private_key_openssh
}

resource "local_file" "public_key" {
  filename = "${path.module}/minimal-ec2-arm-ssh.pub"
  content  = tls_private_key.ssh.public_key_openssh
}

resource "null_resource" "chmod_private" {
  triggers = { fp = tls_private_key.ssh.public_key_fingerprint_md5 }
  provisioner "local-exec" {
    command = "chmod 400 ${path.module}/minimal-ec2-arm-ssh"
  }
  depends_on = [local_sensitive_file.private_key]
}

resource "aws_security_group" "bastion_sg" {
  name        = "bastion-sg"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from operator"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "bastion-sg" }
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.ubuntu_2404_arm64.id
  instance_type               = "t4g.nano"
  subnet_id                   = aws_subnet.public[local.nat_az].id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]

  key_name                    = aws_key_pair.minimal-ec2-arm.key_name

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = false
    tags = {
      Name = "minimal-ec2-arm-root"
    }
  }

  metadata_options {
    http_tokens   = "required"
  }

  tags = { Name = "bastion-${local.nat_az}" }

  depends_on = [null_resource.chmod_private]
}

resource "aws_security_group" "private_web_sg" {
  name   = "private-web-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    description = "SSH from bastion"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  ingress {
    description = "HTTP from bastion"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "private-web-sg" }
}

resource "aws_instance" "web" {
  for_each                     = local.private_subnets
  ami                          = data.aws_ami.ubuntu_2404_arm64.id
  instance_type                = "t4g.micro"
  subnet_id                    = aws_subnet.private[each.key].id
  associate_public_ip_address  = false
  vpc_security_group_ids       = [aws_security_group.private_web_sg.id]
  key_name                     = aws_key_pair.minimal-ec2-arm.key_name

  user_data = <<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y nginx
    systemctl enable nginx
    systemctl start nginx
  EOF

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = false
    tags = { Name = "minimal-ec2-arm-web-root" }
  }

  metadata_options {
    http_tokens = "required"
  }

  tags = { Name = "web-${each.key}" }

  depends_on = [
    aws_nat_gateway.nat,
    aws_route_table_association.private,
  ]
}

resource "aws_security_group" "alb_sg" {
  name   = "alb-sg"
  vpc_id = aws_vpc.main.id

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

  tags = { Name = "alb-sg" }
}

resource "aws_security_group_rule" "web_from_alb" {
  type                     = "ingress"
  description              = "HTTP from ALB"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = aws_security_group.private_web_sg.id
  source_security_group_id = aws_security_group.alb_sg.id
}

resource "aws_lb" "app" {
  name               = "minimal-ec2-arm-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [for s in aws_subnet.public : s.id]
  idle_timeout       = 60

  tags = { Name = "minimal-ec2-arm-alb" }
}

resource "aws_lb_target_group" "web_tg" {
  name        = "tg-web-80"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/"
    matcher             = "200-399"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = { Name = "tg-web-80" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}

resource "aws_lb_target_group_attachment" "web" {
  for_each         = aws_instance.web
  target_group_arn = aws_lb_target_group.web_tg.arn
  target_id        = each.value.id
  port             = 80
}

output "ssh_bastion" {
  value = "ssh -i ${path.module}/minimal-ec2-arm-ssh -o IdentitiesOnly=yes ubuntu@${aws_instance.bastion.public_ip}"
}

output "ssh_web_proxycommand_examples" {
  value = {
    for k, i in aws_instance.web :
    k => join(" ", [
      "ssh",
      "-o", "'ProxyCommand=ssh -i ${path.module}/minimal-ec2-arm-ssh -o IdentitiesOnly=yes ubuntu@${aws_instance.bastion.public_ip} -W %h:%p'",
      "-i", "${path.module}/minimal-ec2-arm-ssh",
      "-o", "IdentitiesOnly=yes",
      "ubuntu@${i.private_ip}"
    ])
  }
}

output "alb_dns_name" {
  value = aws_lb.app.dns_name
}