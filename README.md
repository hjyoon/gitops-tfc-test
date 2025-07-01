# Minimal AWS VPC + EC2 + Nginx

This repo contains Terraform code to:

- Create a VPC, public subnet, and security group
- Launch an Ubuntu EC2 instance with Nginx

Usage (Terraform Cloud VCS):

1. Connect repo to TFC workspace, set AWS credentials  
2. Push changes—TFC auto-applies  
3. Check `nginx_url` output for access
