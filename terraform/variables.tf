variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name, used as prefix for resource naming and tags"
  type        = string
  default     = "rds-fintech-ledger"
}

variable "environment" {
  description = "Environment name (demo, dev, prod)"
  type        = string
  default     = "demo"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.20.0.0/16"
}

# Two AZs is the minimum for an RDS DB Subnet Group, even for a single-AZ instance.
# We reuse the same two AZs across all subnet tiers for consistency.
variable "availability_zones" {
  description = "Availability zones to spread subnets across"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (NAT Gateway lives here)"
  type        = list(string)
  default     = ["10.20.0.0/24", "10.20.1.0/24"]
}

variable "app_subnet_cidrs" {
  description = "CIDR blocks for private application subnets"
  type        = list(string)
  default     = ["10.20.10.0/24", "10.20.11.0/24"]
}

variable "db_subnet_cidrs" {
  description = "CIDR blocks for private database subnets"
  type        = list(string)
  default     = ["10.20.20.0/24", "10.20.21.0/24"]
}

variable "db_port" {
  description = "PostgreSQL port"
  type        = number
  default     = 5432
}

variable "enable_multi_az" {
  description = "Whether RDS runs Multi-AZ. Keep false during active development to save cost; flip to true before final demo/screenshots to validate the resilience pattern, then destroy."
  type        = bool
  default     = false
}
