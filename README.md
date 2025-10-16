# Minimal AWS VPC + EC2 + Nginx

This repository contains Terraform configuration for provisioning a minimal AWS
environment with a public EC2 instance running Nginx.

## Features

- Creates a VPC, public subnet, and internet gateway  
- Configures routing for external access  
- Sets up a security group for HTTP and SSH  
- Generates an SSH key pair automatically  
- Launches an Ubuntu EC2 instance with Nginx installed

## Quick Start (Local)

1. Ensure you have [Terraform ≥ 1.6](https://developer.hashicorp.com/terraform/downloads).  
2. Configure your AWS credentials (via environment variables or AWS CLI).  
3. Initialize the project:
   `terraform init`
4. Review the planned actions:
   `terraform plan`
5. Apply the configuration:
   `terraform apply`
6. After the apply completes:
   - Check the `nginx_url` output for the public endpoint.
   - Use the `ssh_command` output to connect to your instance.

## Usage (Terraform Cloud VCS Workflow)

1. Connect this repository to a Terraform Cloud workspace.  
2. Configure AWS credentials in workspace variables.  
3. Push your changes — Terraform Cloud will automatically plan and apply.  
4. Check the `nginx_url` output for the public Nginx endpoint.  
5. Use the `ssh_command` output to connect to the instance via SSH.

## Notes

- The SSH port (22) is open to all by default. Restrict access to trusted IPs
  for production environments.
- Terraform version 1.6 or later is required.