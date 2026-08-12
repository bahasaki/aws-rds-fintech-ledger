#############################################
# AMI — Amazon Linux 2023
# Ships with SSM Agent pre-installed and running, which is the
# entire reason Session Manager works without any manual agent
# install step.
#############################################

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

#############################################
# User data — bootstrap script
#
# Responsibilities:
#  1. Install Python 3.11 + pip + git
#  2. Pull DB connection details from SSM Parameter Store at boot
#     time (never baked into the AMI or this script as literals)
#  3. Clone the app repo and install dependencies
#  4. Run Alembic migrations
#  5. Start the FastAPI app as a systemd service
#
# Kept intentionally simple for the demo — a real deployment would
# use a pre-baked AMI or container image instead of pulling git +
# pip install at boot, to avoid boot-time dependency on GitHub/PyPI
# availability. That tradeoff belongs in the ADR.
#############################################

locals {
  app_user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail

    dnf install -y python3.11 python3.11-pip git

    # Pull DB config from SSM at boot — nothing DB-related is hardcoded here.
    SSM_PREFIX="/${var.project_name}/${var.environment}/db"
    DB_HOST=$(aws ssm get-parameter --name "$SSM_PREFIX/host" --query 'Parameter.Value' --output text --region ${var.aws_region})
    DB_PORT=$(aws ssm get-parameter --name "$SSM_PREFIX/port" --query 'Parameter.Value' --output text --region ${var.aws_region})
    DB_NAME=$(aws ssm get-parameter --name "$SSM_PREFIX/name" --query 'Parameter.Value' --output text --region ${var.aws_region})
    DB_USER=$(aws ssm get-parameter --name "$SSM_PREFIX/username" --with-decryption --query 'Parameter.Value' --output text --region ${var.aws_region})
    DB_PASS=$(aws ssm get-parameter --name "$SSM_PREFIX/password" --with-decryption --query 'Parameter.Value' --output text --region ${var.aws_region})

    mkdir -p /opt/ledger-app
    cd /opt/ledger-app

    # Values are single-quoted so that shell metacharacters in the
    # password (parentheses, backticks, dollar signs, etc.) are
    # treated as literal characters if this file is ever sourced by
    # a shell, rather than interpreted as shell syntax. See
    # docs/incidents/incident-004 for the failure this prevents.
    cat > .env <<EOT
    DATABASE_URL='postgresql://$${DB_USER}:$${DB_PASS}@$${DB_HOST}:$${DB_PORT}/$${DB_NAME}'
    EOT

    # NOTE: application code deployment (git clone / pip install / alembic
    # upgrade / systemd unit) is deliberately left out of this bootstrap —
    # tracked as the next step once the FastAPI app skeleton exists.
    echo "Bootstrap complete: DB connection details written to /opt/ledger-app/.env"
  EOF
}

#############################################
# App EC2 Instance
# Lives in the private app subnet, no public IP, reachable only via
# SSM Session Manager (through NAT for now — see network ADR).
#############################################

resource "aws_instance" "app" {
  ami                          = data.aws_ami.al2023.id
  instance_type                = "t3.micro"
  subnet_id                    = aws_subnet.app[0].id
  vpc_security_group_ids       = [aws_security_group.app.id]
  iam_instance_profile         = aws_iam_instance_profile.app.name
  associate_public_ip_address  = false

  user_data                   = base64encode(local.app_user_data)
  user_data_replace_on_change = true

  root_block_device {
    # The current AL2023 AMI's underlying snapshot is 30GB — EC2
    # only allows a root volume >= the AMI's snapshot size, never
    # smaller. 30GB is the floor here, not an arbitrary choice.
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "${var.project_name}-app"
  }

  # Ensure SSM parameters exist before the instance boots and tries
  # to read them — avoids a race on first `terraform apply`.
  depends_on = [
    aws_ssm_parameter.db_host,
    aws_ssm_parameter.db_port,
    aws_ssm_parameter.db_name,
    aws_ssm_parameter.db_username,
    aws_ssm_parameter.db_password,
  ]
}
