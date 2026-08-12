# Incident 005: systemd EnvironmentFile Parsing Differs from Shell `source`

**Date:** 2026-08-11 (identified during bootstrap script design, prior to
this specific stack being redeployed with the app running as a service)
**Severity:** Low (design-time finding, caught before deployment)
**Component:** EC2 bootstrap script / systemd unit configuration

## Symptoms

While extending the bootstrap script (`ec2.tf`) to run the FastAPI app as
a long-lived `systemd` service instead of a one-off manual check, the
`.env` file format from Incident 004's fix — single-quoted values,
e.g. `DATABASE_URL='postgresql://...'` — needed to be fed into a systemd
unit via `EnvironmentFile=`.

Reviewing `systemd.exec(5)`'s documented behavior for `EnvironmentFile`
surfaced a difference: `systemd`'s parser for this directive does not
follow POSIX shell quoting rules the same way `sh`'s `source`/`.` does.
Quote characters in an `EnvironmentFile` are not guaranteed to be stripped
the same way they would be by a shell — in some cases they can end up as
literal characters embedded in the resulting environment variable value,
which would silently corrupt `DATABASE_URL` (e.g. producing a connection
string with a stray leading/trailing `'` character) rather than failing
loudly.

## Investigation

This was caught by design review before deployment, not by a failed
`systemctl start` — the risk was identified by reading `systemd.exec(5)`'s
documentation for `EnvironmentFile` while writing the systemd unit block,
prompted by remembering that Incident 004's fix depended specifically on
shell quoting semantics (`source`'s behavior), which does not necessarily
generalize to every other consumer of a `KEY=value` file format.

## Root Cause

`.env`-style `KEY=value` files are not a single standardized format with
one universal parsing rule — different tools that consume them (a POSIX
shell via `source`, Python's `python-dotenv`, `systemd`'s
`EnvironmentFile=`, Docker's `--env-file`, etc.) each implement their own
parsing logic, with different rules for quoting, escaping, and comments.
A fix that makes a file safe for one consumer (shell `source`, per
Incident 004) is not automatically safe for a different consumer.

## Fix

Rather than trying to find a quoting style that happens to work correctly
across every possible consumer of `.env`, the fix moves the safety
guarantee to the point of generation instead of the point of consumption:

- `random_password.db_master`'s `override_special` (in `rds.tf`) already
  excludes shell metacharacters as of Incident 004's fix
  (`"!#%^&*-_=+[]{}<>:?"` — no `(`, `)`, or `$`).
- The bootstrap script's `.env` for the systemd-managed deployment writes
  the value **unquoted**: `DATABASE_URL=postgresql://...`. Because the
  password's character set no longer contains anything that any
  reasonable `KEY=value` parser (shell, systemd, dotenv, etc.) would
  treat as a special character, quoting becomes unnecessary rather than
  differently-necessary per consumer.

This is a deliberate change of strategy from Incident 004: that fix used
*both* character-set restriction and quoting as defense in depth for a
shell-specific consumer. This fix recognizes that quoting doesn't
generalize across consumers, so it leans entirely on the character-set
restriction, which does generalize.

## Verification

Verification for this specific instance is folded into the broader
end-to-end check of the redeployed app: confirming `systemctl status
ledger-app` shows the service active and `curl localhost:8000/health`
returns successfully implies the `EnvironmentFile` was parsed correctly
and `DATABASE_URL` reached the app uncorrupted.

## Prevention

- Treat "safe for shell `source`" and "safe for systemd
  `EnvironmentFile`" (and safe for any other `.env` consumer) as separate
  properties that each need their own verification, not one property
  that transfers automatically between tools.
- When a secret must pass through multiple different parsers across its
  lifecycle (shell scripts, systemd units, application config loaders),
  restricting the secret's character set at generation time is more
  robust than trying to quote/escape correctly for every consumer
  individually — there is exactly one thing to get right instead of N.

## Lessons Learned

This incident didn't happen — it was prevented — which is itself the
point worth recording. Incident 004 fixed a concrete failure for one
specific consumer (`sh`). Extending the same file to a second consumer
(`systemd`) without re-checking the assumption would have reintroduced a
very similar bug in a new form, just delayed until the next place the
`.env` file was read differently. Fixing the underlying generation-time
constraint (Incident 004's character-set restriction) rather than only
the symptom (adding quotes for one consumer) is what made this one
preventable by inspection instead of by another failed deploy.
