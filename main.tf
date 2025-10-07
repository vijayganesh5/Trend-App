###############################################
# Terraform: Jenkins EC2 Setup (VPC + SG + EC2)
# Project: Trend App CI/CD Infrastructure
# Region: ap-south-1
# Author: Vijay Ganesh
###############################################

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

###############################################
# 1. VPC
###############################################
resource "aws_vpc" "trend_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name    = "trend-vpc"
    Project = "TrendApp-CICD"
  }
}

###############################################
# 2. Public Subnet
###############################################
resource "aws_subnet" "trend_subnet" {
  vpc_id                  = aws_vpc.trend_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "trend-public-subnet"
  }
}

###############################################
# 3. Internet Gateway
###############################################
resource "aws_internet_gateway" "trend_igw" {
  vpc_id = aws_vpc.trend_vpc.id

  tags = {
    Name = "trend-igw"
  }
}

###############################################
# 4. Route Table + Association
###############################################
resource "aws_route_table" "trend_rt" {
  vpc_id = aws_vpc.trend_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.trend_igw.id
  }

  tags = {
    Name = "trend-rt"
  }
}

resource "aws_route_table_association" "trend_rta" {
  subnet_id      = aws_subnet.trend_subnet.id
  route_table_id = aws_route_table.trend_rt.id
}

###############################################
# 5. Security Group
###############################################
resource "aws_security_group" "trend_sg" {
  name        = "trend-jenkins-sg"
  description = "Allow SSH, HTTP(3000), Jenkins(8080)"
  vpc_id      = aws_vpc.trend_vpc.id

  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow App Port"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow Jenkins Web UI"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "trend-sg"
  }
}

###############################################
# 6. Key Pair (Auto-generated)
###############################################
resource "tls_private_key" "trend_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "trend_key" {
  key_name   = "trend-key"
  public_key = tls_private_key.trend_key.public_key_openssh
}

# Save private key locally after creation
resource "null_resource" "save_key" {
  provisioner "local-exec" {
    command = "echo '${tls_private_key.trend_key.private_key_openssh}' > trend-key.pem && chmod 600 trend-key.pem"
  }
}

###############################################
# 7. EC2 Instance (Jenkins + Docker)
###############################################
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical (Ubuntu)
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_instance" "jenkins_server" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.medium"
  subnet_id                   = aws_subnet.trend_subnet.id
  vpc_security_group_ids      = [aws_security_group.trend_sg.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.trend_key.key_name

  user_data = <<-EOF
    #!/bin/bash
    set -e
    apt-get update -y
    apt-get install -y openjdk-11-jdk docker.io git curl wget

    systemctl enable --now docker
    usermod -aG docker ubuntu

    curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | tee \
      /usr/share/keyrings/jenkins-keyring.asc > /dev/null
    echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
      https://pkg.jenkins.io/debian-stable binary/ | tee \
      /etc/apt/sources.list.d/jenkins.list > /dev/null
    apt-get update -y
    apt-get install -y jenkins
    usermod -aG docker jenkins

    systemctl enable jenkins
    systemctl start jenkins

    echo "Setup completed successfully!"
    echo "Jenkins Initial Admin Password:" > /home/ubuntu/jenkins-password.txt
    cat /var/lib/jenkins/secrets/initialAdminPassword >> /home/ubuntu/jenkins-password.txt
  EOF

  tags = {
    Name    = "trend-jenkins-ec2"
    Project = "TrendApp-CICD"
  }
}

###############################################
# 8. Elastic IP (Static IP for Jenkins)
###############################################
resource "aws_eip" "jenkins_eip" {
  instance = aws_instance.jenkins_server.id

  tags = {
    Name = "trend-jenkins-eip"
  }
}

###############################################
# 9. Outputs
###############################################
output "jenkins_public_ip" {
  description = "Public IP of Jenkins EC2"
  value       = aws_eip.jenkins_eip.public_ip
}

output "jenkins_url" {
  description = "Jenkins Web UI URL"
  value       = "http://${aws_eip.jenkins_eip.public_ip}:8080"
}

output "ssh_private_key" {
  description = "Private key for SSH access"
  value       = tls_private_key.trend_key.private_key_openssh
  sensitive   = true
}

output "ssh_command" {
  description = "SSH command to connect Jenkins EC2"
  value       = "ssh -i trend-key.pem ubuntu@${aws_eip.jenkins_eip.public_ip}"
}

