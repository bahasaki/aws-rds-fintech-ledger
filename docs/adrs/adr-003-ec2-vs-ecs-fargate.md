# ADR 003: EC2 Instead of ECS Fargate for the Application Compute Layer

## Context

The FastAPI application needs somewhere to run. This portfolio already
contains a project built on ECS Fargate
(`aws-ecs-url-shortener`), so the choice for this project wasn't purely
"which is technically better" — it also had to weigh what the choice
contributes to the portfolio as a whole versus what's fastest to build.

## Decision

Run the application on a single EC2 instance (`terraform/ec2.tf`)
managed by systemd, not on ECS Fargate.

## Alternatives considered

**ECS Fargate.** Already proven in this portfolio's
`aws-ecs-url-shortener` project. Faster to stand up (no AMI selection,
no user-data bootstrap script, no systemd unit to write), and the
container-based deployment model is closer to how many real companies
actually ship services today. Fargate's `execute-command` feature is
the rough equivalent of SSM Session Manager for shell access into a
running task.

**EC2 with systemd (chosen).** Two reasons drove this over reusing the
Fargate pattern:

1. **Portfolio breadth.** A second Fargate-based project would
   demonstrate the same deployment pattern twice. EC2 + SSM Session
   Manager + a hand-written systemd unit is a genuinely different set
   of skills — AMI selection, `user_data` bootstrap scripting, IAM
   instance profiles, and OS-level service management — none of which
   the Fargate project exercises.
2. **DVA-C02 relevance.** This project is explicitly tied to AWS
   Developer Associate certification preparation, and EC2/SSM/user-data
   topics are more heavily represented on that exam than Fargate-specific
   material.

## Consequences

- The bootstrap script (`terraform/ec2.tf`'s `user_data`) does
  meaningfully more work than an equivalent Fargate task definition
  would: installing Python, cloning the repository, creating a virtual
  environment, installing dependencies, running Alembic migrations, and
  writing a systemd unit — all shell scripting that a container image
  would have baked in ahead of time. This is also precisely why
  Incidents 003 through 006 (AMI snapshot size, `.env` shell parsing,
  systemd `EnvironmentFile` semantics, the Alembic ENUM double-create)
  all happened at all — none of them are Fargate-specific failure
  modes; they're consequences of choosing to script a general-purpose
  OS instead of shipping a pre-built container.
- Application updates require either a new EC2 instance (since
  `user_data_replace_on_change = true` forces replacement whenever the
  bootstrap script changes) or a manual `git pull` + service restart
  inside the running instance. Fargate's task definition + rolling
  deployment model handles this more cleanly for a real production
  service; this project accepted that gap deliberately, since
  demonstrating deployment automation wasn't this project's focus (it
  already exists in the ECS project).
- SSM Session Manager (rather than Fargate's `execute-command`) is the
  shell-access mechanism here, which is what let this project also
  demonstrate a no-bastion-host access pattern as its own distinct
  point (see the network architecture notes in the main README).
