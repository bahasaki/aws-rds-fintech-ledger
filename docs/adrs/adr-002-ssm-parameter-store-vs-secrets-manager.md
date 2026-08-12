# ADR 002: SSM Parameter Store (SecureString) Instead of Secrets Manager for Database Credentials

## Context

The application needs to store and retrieve the RDS master password and
connection details somewhere the EC2 instance can read at boot, without
that secret ever being hardcoded in Terraform-managed source, an AMI,
or a Docker image. AWS offers two services that fit this need: SSM
Parameter Store (with the `SecureString` type) and AWS Secrets Manager.

## Decision

Use SSM Parameter Store with `SecureString` type for all database
credentials (`terraform/rds.tf`, the `aws_ssm_parameter` resources),
not Secrets Manager.

## Alternatives considered

**AWS Secrets Manager.** Purpose-built for secrets specifically, with
built-in automatic rotation support (including a native integration for
rotating RDS credentials on a schedule without custom Lambda code), and
fine-grained resource policies. The rotation feature is a genuine
capability gap versus Parameter Store — Parameter Store has no
equivalent built-in rotation mechanism.

**SSM Parameter Store, SecureString (chosen).** Functionally sufficient
for this project's actual need — store an encrypted value, read it at
boot via IAM-authenticated API call, decrypt via KMS. The `kms:ViaService`
IAM condition (`terraform/iam.tf`) scopes decryption narrowly to
requests originating from the SSM service specifically, not a blanket
KMS grant. The primary reason to choose it over Secrets Manager: cost.
Secrets Manager charges per secret per month plus per API call; SSM
Parameter Store's `SecureString` tier used here is free at this volume.
For a portfolio project running intermittently on a limited credit
budget, that difference is not trivial — it is one of several
deliberate cost-conscious choices documented across this project (see
the cost-tracking discussion in this project's working notes).

## Consequences

- No automatic credential rotation exists in this project. If rotation
  were required, it would need to be built manually — updating the
  `random_password` resource, tainting it to force regeneration, and
  updating the SSM parameters and application config in the correct
  order. Secrets Manager's native RDS rotation integration would have
  made this closer to a solved problem.
- The `kms:ViaService` condition (see `terraform/iam.tf`) is necessary
  specifically because Parameter Store's `SecureString` decryption goes
  through KMS as a separate step from the `ssm:GetParameter` call
  itself — an IAM policy scoped to `ssm:GetParameter` alone is not
  sufficient without a corresponding `kms:Decrypt` grant, which is a
  detail Secrets Manager's own resource policies handle more directly
  without a separate KMS condition to reason about.
- If this project ever needed real production-grade secret rotation
  (e.g. for the fintech-realism narrative the ledger app is built
  around), the honest answer in an interview would be: "I chose
  Parameter Store here for cost reasons on a portfolio project: in an
  actual production fintech system I'd default to Secrets Manager for
  the built-in rotation." That tradeoff — and being able to name it
  explicitly — is itself part of what this ADR is meant to demonstrate.
