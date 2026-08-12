output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = aws_subnet.public[*].id
}

output "app_subnet_ids" {
  description = "IDs of private app subnets"
  value       = aws_subnet.app[*].id
}

output "db_subnet_ids" {
  description = "IDs of private db subnets"
  value       = aws_subnet.db[*].id
}

output "app_security_group_id" {
  description = "ID of the app security group"
  value       = aws_security_group.app.id
}

output "db_security_group_id" {
  description = "ID of the db security group"
  value       = aws_security_group.db.id
}

output "ssm_endpoints_security_group_id" {
  description = "ID of the SSM VPC endpoints security group"
  value       = aws_security_group.ssm_endpoints.id
}

output "nat_gateway_public_ip" {
  description = "Public (Elastic) IP of the NAT Gateway"
  value       = aws_eip.nat.public_ip
}

output "rds_endpoint" {
  description = "RDS instance connection endpoint (host:port)"
  value       = aws_db_instance.main.endpoint
}

output "rds_address" {
  description = "RDS instance hostname only"
  value       = aws_db_instance.main.address
}

output "app_instance_profile_name" {
  description = "IAM instance profile name to attach to the app EC2 instance"
  value       = aws_iam_instance_profile.app.name
}

output "db_credentials_ssm_path" {
  description = "SSM Parameter Store path prefix where DB credentials live"
  value       = "/${var.project_name}/${var.environment}/db/"
}

output "app_instance_id" {
  description = "EC2 instance ID for the app — use with SSM Session Manager"
  value       = aws_instance.app.id
}
