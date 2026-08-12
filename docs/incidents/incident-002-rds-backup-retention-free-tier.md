# Incident 002: RDS Creation Failed — Backup Retention Exceeds Free Tier Limit

**Date:** 2026-08-11
**Severity:** Low (blocked `terraform apply`, no live infrastructure affected)
**Component:** Terraform / AWS RDS

## Symptoms

After fixing Incident 001, `terraform apply` progressed past security group
creation and began creating the RDS instance, then failed:

```
aws_security_group.db: Creation complete after 3s [id=sg-0acb8456a92e7527c]
aws_db_instance.main: Creating...

Error: creating RDS DB Instance (rds-fintech-ledger-demo): operation error RDS:
CreateDBInstance, https response error StatusCode: 400, RequestID: ...,
api error FreeTierRestrictionError: The specified backup retention period
exceeds the maximum available to free tier customers. To remove all
limitations, upgrade your account plan.
```

## Investigation

The error is explicit about the cause: `FreeTierRestrictionError` tied
specifically to `backup_retention_period`. The value configured in
`rds.tf` was `7` (days), chosen as a reasonable production-like default
without checking it against this AWS account's tier restrictions.

This account is a relatively new AWS account still under free-tier
eligibility, which caps certain RDS parameters — `backup_retention_period`
being one of them — below what a standard/full account allows.

## Root Cause

Free-tier AWS accounts enforce a lower ceiling on `backup_retention_period`
than a full-billing account. `terraform plan` has no visibility into
account-level tier restrictions — it only validates syntax and provider
schema, not account-specific service quotas — so this was invisible until
the live `CreateDBInstance` API call was actually made.

## Fix

Reduced `backup_retention_period` from `7` to `1`:

```diff
- backup_retention_period = 7
+ # Free-tier accounts cap backup_retention_period at 1 day — AWS
+ # rejects anything higher with FreeTierRestrictionError. 1 day is
+ # still enough to demonstrate the backup/restore drill; a real
+ # prod environment on a full account would use 7-35 days instead.
+ backup_retention_period = 1
```

Re-ran `terraform apply`; RDS instance creation proceeded and completed.

## Verification

- `terraform apply` created `aws_db_instance.main` successfully with
  `backup_retention_period = 1`.
- RDS console/CLI confirmed the instance reached `available` status.

## Prevention

- Document known free-tier ceilings for this account (backup retention,
  Multi-AZ cost implications, instance class eligibility) in an ADR so
  future projects on this same account don't hit the same wall blind.
- For any RDS-related IaC on a free-tier account, default to the most
  conservative value first (`1` day) and only raise it deliberately with
  an explicit note about the tier implication, rather than starting from
  a "production-reasonable" default and discovering the ceiling via a
  failed apply.

## Lessons Learned

Free-tier restrictions are enforced at the account level by the live
service API, not by anything visible in Terraform's provider schema or
`plan` output. This is a second, distinct example (after Incident 001) of
a category of failure that `terraform plan` structurally cannot catch:
account-specific runtime service restrictions, as opposed to static
configuration errors. A plan being "clean" does not guarantee an apply
will succeed — some constraints only exist server-side, tied to the
specific account, not the resource configuration itself.
