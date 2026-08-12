# Incident 001: Security Group Creation Failed — Non-ASCII Character in Description

**Date:** 2026-08-11
**Severity:** Low (blocked `terraform apply`, no live infrastructure affected)
**Component:** Terraform / AWS EC2 Security Group

## Symptoms

`terraform apply` failed partway through, after VPC, subnets, and route tables
had already been created successfully:

```
Error: creating Security Group (rds-fintech-ledger-db-sg): operation error EC2:
CreateSecurityGroup, https response error StatusCode: 400, RequestID: ...,
api error InvalidParameterValue: Value (Security group for RDS PostgreSQL —
only reachable from app-sg) for parameter GroupDescription is invalid.
Character sets beyond ASCII are not supported.
```

## Investigation

The error message pointed directly at `GroupDescription` as the invalid
parameter, with the exact string included in the error. Comparing that
string against `security-groups.tf` showed an em dash (`—`) inside the
`description` field of `aws_security_group.db`.

A repo-wide search confirmed this was the only `description` field (i.e.
a value actually sent to an AWS API, not a Terraform-internal comment) that
contained a non-ASCII character:

```bash
grep -n "description.*=.*—" *.tf
```

Every other instance of `—` in the codebase was inside a `#`-prefixed
Terraform comment, which never reaches the AWS API and was not the cause.

## Root Cause

The AWS EC2 API enforces a strict ASCII-only constraint on `GroupDescription`
for security groups. Typographic characters commonly used for readability in
written English (em dash, smart quotes, etc.) are not ASCII and are rejected
outright with `InvalidParameterValue`.

The description had been written with an em dash purely as a stylistic
choice, with no awareness that this specific AWS field enforces ASCII.

## Fix

Replaced the em dash with a standard ASCII hyphen:

```diff
- description = "Security group for RDS PostgreSQL — only reachable from app-sg"
+ description = "Security group for RDS PostgreSQL - only reachable from app-sg"
```

Re-ran `terraform apply`; the security group was created successfully on the
next attempt, and Terraform correctly skipped all previously-created
resources (VPC, subnets, route tables) without re-creating them.

## Verification

- `terraform apply` proceeded past the `aws_security_group.db` resource
  without error.
- Confirmed no other executable string field (`description`, tag values,
  names) in the codebase contained non-ASCII characters, via a full-repo
  grep excluding comment lines.

## Prevention

- Stick to plain ASCII punctuation (`-`, `'`, `"`) in any Terraform string
  that is passed to an AWS API field, not just comments. Comments are safe;
  resource arguments are not.
- A pre-commit hook or simple CI grep step (`grep -RP '[^\x00-\x7F]' *.tf`
  scoped to non-comment lines) would catch this class of error before
  `apply` time in future projects.

## Lessons Learned

`terraform plan` does not catch this — it's a client-side rendering of
intended changes and doesn't validate field-level constraints enforced only
by the live AWS API. This is a good example of an error class that only
surfaces at `apply` time, no matter how carefully the plan is reviewed
beforehand.
