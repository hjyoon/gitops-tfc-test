# Minimal AWS VPC + Bastion + Private EC2 + ALB (Nginx)

Provision **VPC + public/private subnets + 1 NAT + Bastion + 2 private EC2 + ALB(HTTP)** with Terraform.
All values are fixed via `locals`. After apply, access Nginx through the ALB.

## Create (Local)

```bash
terraform init
terraform plan
terraform apply
```

## Check

```bash
# ALB DNS (open in browser to see Nginx default page)
terraform output alb_dns_name

# Bastion SSH command
terraform output -raw ssh_bastion

# Proxy SSH examples to private EC2s (map)
terraform output ssh_web_proxycommand_examples
```

## Components

- VPC (CIDR 10.10.0.0/16)
- AZs: ap-northeast-2a, ap-northeast-2c
- 2 public + 2 private subnets
- 1 IGW, 1 NAT GW (in 2a)
- Bastion (public subnet, SSH entry)
- 2 Web EC2 (private, t4g.micro, Nginx via user_data)
- ALB (HTTP:80) → target: EC2 instances

## Security / Cost Notes

- bastion_sg opens 22/tcp to 0.0.0.0/0 for demo → restrict to trusted IPs in production.
- NAT/ALB/EIP incur costs → destroy after testing.

## Destroy

```bash
terraform destroy
```