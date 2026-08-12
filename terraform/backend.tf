#############################################
# Remote state backend.
#
# bucket value below must match the output from terraform-bootstrap/
# after that config has been applied. Terraform backend blocks
# cannot use variables — this is necessarily hardcoded here, which
# is exactly why it's bootstrapped by a separate, rarely-touched
# config rather than generated fresh on every apply.
#
# ACCOUNT_ID is this AWS account's ID (774493573578) baked into the
# bucket name by the bootstrap config to guarantee global uniqueness.
#
# Locking uses S3-native locking (use_lockfile) rather than a
# DynamoDB table. This is the newer mechanism (Terraform 1.11+ /
# AWS provider 5.x+): a lock file is written directly into the S3
# bucket instead of a row in a separate DynamoDB table. The
# terraform-bootstrap/ DynamoDB table is no longer required by this
# backend — see ADR for the migration note (dynamodb_table param is
# deprecated as of this provider version but still functional).
#############################################

terraform {
  backend "s3" {
    bucket       = "rds-fintech-ledger-tfstate-774493573578"
    key          = "main/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
