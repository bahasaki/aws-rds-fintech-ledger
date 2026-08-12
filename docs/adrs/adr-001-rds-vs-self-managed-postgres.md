# ADR 001: Managed RDS PostgreSQL Instead of Self-Managed PostgreSQL on EC2

## Context

The application needs a PostgreSQL database. Two broad options exist on
AWS: run PostgreSQL on EC2 and manage it directly, or use RDS, AWS's
managed relational database service.

This decision matters for a portfolio project specifically because it's
a choice interviewers ask about directly — "when would you choose RDS
over self-managed, and why" is a common backend/infra interview
question, and having actually built both (this project uses RDS; a
self-managed Postgres-on-EC2 setup exists in an earlier portfolio
project) gives a concrete basis for answering it rather than reciting
tradeoffs from documentation.

## Decision

Use RDS PostgreSQL, not a self-managed instance on EC2.

## Alternatives considered

**Self-managed PostgreSQL on EC2.** Full control over the exact
PostgreSQL configuration, no RDS service limitations (e.g. no
superuser access is available on RDS — some extensions and
configuration options are restricted), and no RDS pricing premium over
raw EC2 + EBS cost. The cost saving is real but modest at this scale
(a db.t3.micro-equivalent self-managed setup is cheaper, but the
difference is a few dollars a month, not a structural saving).

**RDS PostgreSQL (chosen).** AWS handles patching, automated backups,
snapshot management, and Multi-AZ failover without any custom tooling.
Point-in-time recovery is built in. Storage autoscaling
(`max_allocated_storage`) is a single Terraform argument instead of a
manually monitored EBS volume with a resize runbook. The tradeoff is
less control (no superuser, no arbitrary extensions, no direct
filesystem access to the data directory) and a modest cost premium over
raw compute+storage.

## Consequences

- Patching and minor-version upgrades are AWS's responsibility, not
  something this project's Terraform or runbooks need to handle.
- The backup/restore drill exercised in this project
  (`docs/runbooks/backup-restore-drill.md`) is meaningfully simpler
  than it would be for a self-managed instance — `aws rds
  create-db-snapshot` / `restore-db-instance-from-db-snapshot` replace
  what would otherwise be a custom `pg_dump`/`pg_basebackup` and
  restore procedure that this project would have had to build and test
  itself.
- Some operational levers are unavailable: no direct filesystem access
  for investigating disk-level issues, no ability to install arbitrary
  PostgreSQL extensions that RDS doesn't allow-list, no superuser role.
  None of these constraints affected this project's actual
  requirements, but they are the concrete price of the tradeoff.
- Multi-AZ (toggled via `enable_multi_az` in `terraform/variables.tf`)
  is a single boolean here. On self-managed EC2, achieving the
  equivalent (synchronous standby, automatic failover) would require
  building and testing that failover mechanism directly — a
  significant undertaking this project deliberately avoided by choosing
  RDS.
