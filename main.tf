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

  tags = {
    Name = "minimal-vpc"
  }
}

data "aws_availability_zones" "available" {}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.10.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "minimal-public-subnet"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "minimal-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "minimal-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "ec2_nginx" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
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

  tags = {
    Name = "ec2-nginx"
  }
}

resource "tls_private_key" "ssh" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "minimal" {
  key_name   = "minimal-ssh"
  public_key = tls_private_key.ssh.public_key_openssh
}

resource "local_sensitive_file" "private_key" {
  filename = "${path.module}/minimal-ssh"
  content  = tls_private_key.ssh.private_key_openssh
}

resource "local_file" "public_key" {
  filename = "${path.module}/minimal-ssh.pub"
  content  = tls_private_key.ssh.public_key_openssh
}

resource "null_resource" "chmod_private" {
  triggers = { fp = tls_private_key.ssh.public_key_fingerprint_md5 }
  provisioner "local-exec" {
    command = "chmod 400 ${path.module}/minimal-ssh"
  }
  depends_on = [local_sensitive_file.private_key]
}

resource "aws_instance" "minimal" {
  ami                    = "ami-0662f4965dfc70aca" # Ubuntu Server 24.04 LTS (64-bit (x86))
  instance_type          = "t3.nano"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ec2_nginx.id]

  key_name = aws_key_pair.minimal.key_name

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = false
    tags = {
      Name = "minimal-root"
    }
  }

  user_data = <<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y nginx
    systemctl enable nginx
    systemctl start nginx
  EOF

  tags = {
    Name = "minimal-ec2"
  }

  depends_on = [null_resource.chmod_private]
}

output "ssh_command" {
  value     = "ssh -i ${path.module}/minimal-ssh ubuntu@${aws_instance.minimal.public_ip}"
  sensitive = false
}

output "nginx_url" {
  description = "URL to access nginx on the EC2 instance"
  value       = format("http://%s/", aws_instance.minimal.public_ip)
}
