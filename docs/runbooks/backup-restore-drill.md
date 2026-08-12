# Runbook: RDS Backup / Restore Drill

**Purpose:** Verify that this project's RDS instance can actually be
recovered from a manual snapshot after data loss — not just that backups
are configured, but that a restore genuinely produces usable data. This
drill directly addresses a gap identified in the broader portfolio: prior
projects had never exercised a real backup/restore path end to end.

**Last run:** 2026-08-12
**Result:** Success — restored data matched pre-incident state exactly.

---

## When to run this

- After any schema change, to confirm backups still restore cleanly
  against the current schema.
- Periodically as a standing exercise, the same way a real team would
  run a DR game day — not just once and never touched again.
- Before any production-like demo, as a confidence check that the
  documented recovery path still works.

## Prerequisites

- AWS CLI configured with credentials for account `774493573578`.
- The RDS instance (`rds-fintech-ledger-demo`) and its DB subnet group /
  security group already exist (created by `terraform/rds.tf`).
- SSM Session Manager access to the app EC2 instance, for querying the
  database from inside the VPC (the DB has no public access — see
  `docs/adrs` for that decision).

## Cost note

A manual snapshot and a temporary restored instance both incur cost for
as long as they exist. This drill is designed to be **demonstrational**:
the restored instance is deleted immediately after verification, and
only the snapshot itself is left behind afterward (snapshot storage cost
is minimal for a database this size). Do not leave a restored instance
running longer than needed to verify it.

---

## Procedure

### 1. Record a "known good" baseline

Before touching anything, capture the current state of the tables that
matter, so there's something concrete to compare against after restore.

```bash
DBURL="postgresql://<user>:<password>@<rds-endpoint>:5432/ledger"

psql "$DBURL" -c "SELECT * FROM transactions;"
psql "$DBURL" -c "SELECT * FROM entries;"
```

**Actual baseline from this run:**

| Table | Row | Key fields |
|---|---|---|
| transactions | `5eb279b6-0ffa-4010-8d26-1c7adee184a4` | "Client payment received" |
| entries | `70527449-1557-4a16-a940-ddd1c278dbdc` | account `8fc752e6...`, amount `100.0000` |
| entries | `18d28dfa-4fec-43b6-8153-5085125dddab` | account `9abb9485...`, amount `-100.0000` |

### 2. Create a manual snapshot

Manual snapshots (as opposed to the automated daily backup) give an
explicit, named recovery point to restore from — not dependent on
whatever the most recent automated backup happens to be.

```bash
aws rds create-db-snapshot \
  --db-instance-identifier rds-fintech-ledger-demo \
  --db-snapshot-identifier rds-fintech-ledger-drill-snapshot-1 \
  --region us-east-1
```

Wait for it to become available (took a few minutes for this instance's
size):

```bash
aws rds wait db-snapshot-available \
  --db-snapshot-identifier rds-fintech-ledger-drill-snapshot-1 \
  --region us-east-1
```

### 3. Simulate the incident

Delete the transaction and its entries to simulate an accidental data
loss event. Entries must be deleted before the transaction they
reference, since there is a foreign key from `entries.transaction_id` to
`transactions.id` without `ON DELETE CASCADE`.

```bash
psql "$DBURL" -c "DELETE FROM entries WHERE transaction_id = '5eb279b6-0ffa-4010-8d26-1c7adee184a4';"
psql "$DBURL" -c "DELETE FROM transactions WHERE id = '5eb279b6-0ffa-4010-8d26-1c7adee184a4';"
```

Confirm the data is actually gone:

```bash
psql "$DBURL" -c "SELECT * FROM transactions;"
```

Expected: `(0 rows)`.

### 4. Restore the snapshot into a new instance

RDS cannot restore a snapshot "in place" onto an existing instance — a
restore always creates a **new** DB instance. Point it at the same
subnet group and security group as the original, so it's reachable from
the same app EC2 instance for verification.

```bash
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier rds-fintech-ledger-drill-restore \
  --db-snapshot-identifier rds-fintech-ledger-drill-snapshot-1 \
  --db-subnet-group-name rds-fintech-ledger-db-subnet-group \
  --vpc-security-group-ids <db-security-group-id> \
  --no-publicly-accessible \
  --region us-east-1
```

Wait for it to come up (took several minutes):

```bash
aws rds wait db-instance-available \
  --db-instance-identifier rds-fintech-ledger-drill-restore \
  --region us-east-1
```

Get its endpoint:

```bash
aws rds describe-db-instances \
  --db-instance-identifier rds-fintech-ledger-drill-restore \
  --region us-east-1 \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text
```

### 5. Verify the restored data

From the app EC2 instance (same VPC, same credentials — a snapshot
restore preserves the master username/password from the source
instance):

```bash
DBURL_RESTORED="postgresql://<user>:<password>@<restored-endpoint>:5432/ledger"

psql "$DBURL_RESTORED" -c "SELECT * FROM transactions;"
psql "$DBURL_RESTORED" -c "SELECT * FROM entries;"
```

**Actual result from this run:** the restored instance contained exactly
the transaction and both entries from the Step 1 baseline — the same
IDs, amounts, and timestamps — confirming the data "deleted" in Step 3
was never actually lost, only removed from the live instance.

### 6. Clean up the temporary restored instance

```bash
aws rds delete-db-instance \
  --db-instance-identifier rds-fintech-ledger-drill-restore \
  --skip-final-snapshot \
  --region us-east-1
```

The manual snapshot from Step 2 is intentionally left in place afterward
as evidence the recovery point exists and works — only the temporary
compute (the restored instance) is torn down.

### 7. Restore the live instance to its pre-drill state

Since this drill intentionally deleted real data from the live instance
to simulate an incident, and the restore target was a separate temporary
instance rather than the live one, the live instance's data needs to be
put back manually so the demo environment isn't left empty:

```bash
psql "$DBURL" -c "INSERT INTO transactions (id, description, created_at) VALUES ('5eb279b6-0ffa-4010-8d26-1c7adee184a4', 'Client payment received', '2026-08-12 13:19:39.217441+00');"
psql "$DBURL" -c "INSERT INTO entries (id, transaction_id, account_id, amount, created_at) VALUES ('70527449-1557-4a16-a940-ddd1c278dbdc', '5eb279b6-0ffa-4010-8d26-1c7adee184a4', '8fc752e6-75a5-445d-9c4f-d453622c86ff', 100.0000, '2026-08-12 13:19:39.221824+00');"
psql "$DBURL" -c "INSERT INTO entries (id, transaction_id, account_id, amount, created_at) VALUES ('18d28dfa-4fec-43b6-8153-5085125dddab', '5eb279b6-0ffa-4010-8d26-1c7adee184a4', '9abb9485-b405-415c-b4cb-95e0a57ba26f', -100.0000, '2026-08-12 13:19:39.221839+00');"
```

In a real incident this step would not exist — the whole point of a real
restore is that the restored instance *becomes* the live one (e.g. via a
DNS/connection-string cutover), rather than being torn down. It only
exists here because this drill deliberately chose the cheaper,
demonstrational path over promoting the restored instance to production,
as documented in the ADR for this decision.

---

## What this drill proves

- The automated/manual snapshot mechanism actually produces a restorable
  artifact, not just a "backup enabled" checkbox.
- Restoring a snapshot into a fresh instance, in the same private
  subnets and security group as the original, works without any manual
  network reconfiguration — the existing Terraform-managed subnet group
  and security group are directly reusable for a restore target.
- Master credentials carry over from the snapshot, so no separate
  credential provisioning step is needed to access a restored instance.
- Foreign key constraints between `entries` and `transactions` matter for
  cleanup order during an incident simulation, not just during normal
  application writes.

## What this drill does not cover (future work)

- Point-in-time recovery (restoring to a specific timestamp rather than
  a named snapshot) — not exercised here.
- Cutover procedure for promoting a restored instance to become the
  live one (updating the app's `DATABASE_URL` / SSM parameter, DNS, etc.)
  — this drill deliberately avoided that path; a real incident response
  runbook would need to document it.
- Restore time objective (RTO) measurement — the restore in this run
  took several minutes, but no formal SLA was measured or targeted.
