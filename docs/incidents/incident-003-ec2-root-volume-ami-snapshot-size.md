# Incident 003: EC2 Instance Creation Failed — Root Volume Smaller Than AMI Snapshot

**Date:** 2026-08-11
**Severity:** Low (blocked `terraform apply`, no live infrastructure affected)
**Component:** Terraform / AWS EC2

## Symptoms

After fixing Incidents 001 and 002, `terraform apply` progressed through
VPC, security groups, RDS, IAM, and SSM parameters, then failed on EC2
instance creation:

```
aws_ssm_parameter.db_name: Creation complete after 0s [id=/rds-fintech-ledger/demo/db/name]
aws_instance.app: Creating...

Error: creating EC2 Instance: operation error EC2: RunInstances, https response
error StatusCode: 400, RequestID: ...,
api error InvalidBlockDeviceMapping: Volume of size 20GB is smaller than
snapshot 'snap-0fa576bea6acca344', expect size >= 30GB
```

## Investigation

The error is unambiguous: the root EBS volume requested (20GB, set in
`root_block_device.volume_size` in `ec2.tf`) is smaller than the snapshot
backing the resolved AMI. The AMI itself was selected dynamically via a
`data "aws_ami" "al2023"` filter for the most recent Amazon Linux 2023 image
— by design, so the project always picks up the latest AL2023 release rather
than pinning to a specific, potentially stale AMI ID.

The specific AMI resolved at apply time (`ami-0260fb21be1fd50db`, per the
apply log) has a 30GB backing snapshot — larger than the 20GB assumed when
`ec2.tf` was originally written.

## Root Cause

EC2 requires a root EBS volume to be greater than or equal to the size of
the AMI's backing snapshot; it can never be smaller, only equal or larger.
Because the AMI is resolved dynamically (`most_recent = true`), its snapshot
size is not fixed at write-time and can grow between when infrastructure
code is written and when it's actually applied, as Amazon updates the
AL2023 base image over time.

The original `volume_size = 20` was an assumption made without querying the
actual current AMI snapshot size at the time the Terraform code was written.

## Fix

Increased `root_block_device.volume_size` from `20` to `30`, with a comment
explaining why 30 is a floor rather than an arbitrary choice:

```diff
  root_block_device {
-   volume_size = 20
+   # The current AL2023 AMI's underlying snapshot is 30GB — EC2
+   # only allows a root volume >= the AMI's snapshot size, never
+   # smaller. 30GB is the floor here, not an arbitrary choice.
+   volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }
```

Re-ran `terraform apply`; the EC2 instance was created successfully
(`i-07bf06711d168adb0`) in 13 seconds.

## Verification

- `terraform apply` completed the `aws_instance.app` resource without error.
- SSM Session Manager confirmed the instance came up healthy and reachable
  (`Ping status: Online`, `Node state: running`).

## Prevention

- When using a dynamically-resolved AMI (`most_recent = true`), treat the
  root volume size as something to verify against the actual resolved AMI,
  not a value chosen once and left static — the underlying snapshot size is
  not guaranteed to stay constant across AMI refreshes.
- Cost impact of the fix is negligible (30GB vs 20GB gp3 is roughly a
  fraction of a dollar per month difference) — the correct response here is
  simply "size to at least the AMI's floor," not an attempt to minimize
  storage at the cost of a failed apply.

## Lessons Learned

This is the third consecutive incident (after 001 and 002) that only
surfaced at `apply` time rather than `plan` time — but for a different
underlying reason than the first two. Incidents 001 and 002 were about
static configuration values violating API-side rules (ASCII-only field,
account-tier ceiling). This one is about a *dynamic* dependency: the AMI ID
itself is only resolved during apply, so any constraint tied to that
specific AMI (like its snapshot size) is fundamentally unknowable at the
time the Terraform code is written, only knowable at the moment it runs
against the live account.
