#############################################
# Random master password
# Generated once, stored in SSM Parameter Store as SecureString.
# Never written to state in plaintext-visible outputs, never
# committed to git. Terraform state itself does contain it — see
# ADR-002 for the state encryption/access-control story.
#############################################

resource "random_password" "db_master" {
  length  = 24
  special = true
  # RDS disallows '/', '@', '"', and space in the password.
  # Also excludes shell metacharacters ( ) ` $ that broke a naive
  # `source .env` in Incident 004 — see docs/incidents/incident-004.
  # Still broad enough for strong entropy without those specific risks.
  override_special = "!#%^&*-_=+[]{}<>:?"

  # Without this, certain provider/state operations can trigger a
  # regeneration of this password on a later `apply`, silently
  # desyncing it from both the live RDS instance and the SSM
  # parameter that already holds the "old" value. Locking it down
  # here means a real password rotation has to be a deliberate,
  # explicit action (taint + apply), not an accidental side effect.
  lifecycle {
    ignore_changes = [
      length,
      special,
      override_special,
    ]
  }
}

#############################################
# DB Subnet Group
# Ties RDS to our private DB subnets specifically. RDS requires
# subnets in at least 2 AZs here even for a single-AZ instance —
# Multi-AZ makes that requirement load-bearing rather than just a
# formality, since the standby actually lives in the second AZ.
#############################################

resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.db[*].id

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

#############################################
# RDS Parameter Group
# Placeholder for custom PostgreSQL settings. Starting from defaults
# and adjusting here (e.g. log_statement, shared_buffers tuning) is
# a deliberate "we can prove this was a conscious choice, not just
# accepted RDS defaults" artifact for interviews.
#############################################

resource "aws_db_parameter_group" "postgres" {
  name   = "${var.project_name}-pg16-params"
  family = "postgres16"

  parameter {
    name  = "log_min_duration_statement"
    value = "1000" # log queries slower than 1s — cheap first pass at slow-query visibility
  }

  tags = {
    Name = "${var.project_name}-pg16-params"
  }
}

#############################################
# RDS Instance — Multi-AZ PostgreSQL
#
# Multi-AZ chosen deliberately over single-AZ to demonstrate the
# synchronous-standby / automatic-failover pattern in the ADR, even
# though it costs more and isn't free-tier eligible. Single-AZ
# db.t3.micro alone would be free-tier eligible; documented as the
# cost-vs-resilience tradeoff this project exists to showcase.
#############################################

resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-${var.environment}"

  engine         = "postgres"
  engine_version = "16.4"
  instance_class = "db.t3.micro"

  allocated_storage     = 20
  max_allocated_storage = 100 # enables storage autoscaling up to 100GB
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = "ledger"
  username = "ledger_admin"
  password = random_password.db_master.result
  port     = var.db_port

  multi_az                = var.enable_multi_az
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  parameter_group_name   = aws_db_parameter_group.postgres.name

  # No public access — this is the DB tier's entire reason to exist.
  publicly_accessible = false

  # Free-tier accounts cap backup_retention_period at 1 day — AWS
  # rejects anything higher with FreeTierRestrictionError. 1 day is
  # still enough to demonstrate the backup/restore drill; a real
  # prod environment on a full account would use 7-35 days instead.
  backup_retention_period = 1
  backup_window           = "03:00-04:00"
  maintenance_window      = "mon:04:30-mon:05:30"

  # Demo project: skip final snapshot to allow clean `terraform destroy`.
  # In a real prod environment this would be `false` with
  # deletion_protection = true instead.
  skip_final_snapshot = true
  deletion_protection = false

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  tags = {
    Name = "${var.project_name}-${var.environment}"
  }
}

#############################################
# SSM Parameter Store — SecureString for app credentials
# The app reads these at startup via its IAM role rather than
# environment variables baked into an image or a .env file in git.
#############################################

resource "aws_ssm_parameter" "db_host" {
  name  = "/${var.project_name}/${var.environment}/db/host"
  type  = "String"
  value = aws_db_instance.main.address
}

resource "aws_ssm_parameter" "db_port" {
  name  = "/${var.project_name}/${var.environment}/db/port"
  type  = "String"
  value = tostring(aws_db_instance.main.port)
}

resource "aws_ssm_parameter" "db_name" {
  name  = "/${var.project_name}/${var.environment}/db/name"
  type  = "String"
  value = aws_db_instance.main.db_name
}

resource "aws_ssm_parameter" "db_username" {
  name  = "/${var.project_name}/${var.environment}/db/username"
  type  = "SecureString"
  value = aws_db_instance.main.username
}

resource "aws_ssm_parameter" "db_password" {
  name  = "/${var.project_name}/${var.environment}/db/password"
  type  = "SecureString"
  value = random_password.db_master.result
}
