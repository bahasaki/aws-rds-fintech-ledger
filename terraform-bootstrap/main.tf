#############################################
# Terraform State Backend Bootstrap
#
# This is a deliberately separate, one-time-apply Terraform config.
# It cannot live in the main terraform/ directory because that
# directory's own state will be stored in the S3 bucket this
# config creates — a classic chicken-and-egg problem. Bootstrap
# this once with LOCAL state, then never touch it again unless
# the backend itself needs to change.
#
# Apply order:
#   1. cd terraform-bootstrap && terraform init && terraform apply
#   2. Note the bucket name and table name from outputs
#   3. cd ../terraform && terraform init (with backend config pointing
#      at those resources — see backend.tf in the main directory)
#############################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform-bootstrap"
      Purpose   = "state-backend"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "rds-fintech-ledger"
}

# Bucket names are globally unique across all of AWS, so we suffix
# with the account ID to avoid collisions without needing a random
# suffix that would be annoying to reference later.
data "aws_caller_identity" "current" {}

locals {
  bucket_name = "${var.project_name}-tfstate-${data.aws_caller_identity.current.account_id}"
  table_name  = "${var.project_name}-tflock"
}

#############################################
# S3 bucket for state — versioned so a bad apply's state is
# recoverable, encrypted at rest, and fully blocked from public
# access (state can contain sensitive values like the RDS password).
#############################################

resource "aws_s3_bucket" "tfstate" {
  bucket = local.bucket_name

  # Prevents accidental `terraform destroy` of the bucket that holds
  # every other stack's state. Remove manually if this project is
  # ever fully decommissioned.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#############################################
# DynamoDB table for state locking.
#
# NOTE: main/backend.tf has since migrated to S3-native locking
# (use_lockfile = true) instead of this table, since the
# dynamodb_table backend parameter is deprecated as of Terraform
# 1.11+ / AWS provider 5.x+. This table is no longer read by the
# main stack's backend config.
#
# Left defined (not deleted) so a stray `terraform apply` here
# doesn't destroy it out from under anyone still referencing it,
# and so the migration itself has a clear before/after paper trail
# for the ADR. Safe to remove in a future cleanup pass once we're
# confident nothing depends on it.
#############################################

resource "aws_dynamodb_table" "tflock" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

output "state_bucket_name" {
  value = aws_s3_bucket.tfstate.id
}

output "lock_table_name" {
  value = aws_dynamodb_table.tflock.name
}
