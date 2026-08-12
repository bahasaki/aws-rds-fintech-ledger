#############################################
# App Security Group
# Attached to the EC2/ECS instances running the FastAPI app.
#############################################

resource "aws_security_group" "app" {
  name        = "${var.project_name}-app-sg"
  description = "Security group for application layer"
  vpc_id      = aws_vpc.main.id

  # Inbound HTTP/API traffic — tighten to a specific ALB SG or CIDR
  # in a real deployment. Left open on 8000 for demo/testing via SSM
  # port forwarding rather than a public listener.
  ingress {
    description = "App port from within VPC"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-app-sg"
  }
}

#############################################
# DB Security Group
# The core "SG chaining" pattern: the ingress rule's source is the
# app SG's ID, not a CIDR block. Only traffic originating from
# something wearing the app-sg "badge" is allowed in — regardless
# of that resource's actual IP address. If the app instance is
# replaced and gets a new private IP, access keeps working with
# zero changes here.
#############################################

resource "aws_security_group" "db" {
  name        = "${var.project_name}-db-sg"
  description = "Security group for RDS PostgreSQL - only reachable from app-sg"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from app tier only"
    from_port       = var.db_port
    to_port         = var.db_port
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  # No egress rule needed for RDS in typical setups, but Terraform/AWS
  # default behavior requires explicit rules if we want to restrict it.
  # We allow outbound within the VPC only — RDS doesn't need internet access.
  egress {
    description = "Outbound within VPC only"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name = "${var.project_name}-db-sg"
  }
}

#############################################
# SSM VPC Endpoints Security Group
# Required if using SSM Session Manager to reach app instances that
# have no public IP and no direct internet-based path to SSM.
# (Endpoints resource block lives in a separate file: ssm-endpoints.tf,
# added once we get to the compute layer.)
#############################################

resource "aws_security_group" "ssm_endpoints" {
  name        = "${var.project_name}-ssm-endpoints-sg"
  description = "Allows HTTPS from app tier to SSM VPC interface endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTPS from app tier"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-ssm-endpoints-sg"
  }
}
