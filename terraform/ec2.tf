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
#  1. Install Python 3.11 + pip + git + PostgreSQL client
#  2. Pull DB connection details from SSM Parameter Store at boot
#     time (never baked into the AMI or this script as literals)
#  3. Clone the app repo (public — see ADR on repo visibility) and
#     install dependencies into a venv
#  4. Run Alembic migrations against the live RDS instance
#  5. Start the FastAPI app as a systemd service, so it survives
#     reboots and restarts automatically on crash
#############################################

locals {
  app_repo_url = "https://github.com/bahasaki/aws-rds-fintech-ledger.git"

  app_user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail

    dnf install -y python3.11 python3.11-pip git postgresql16

    # Pull DB config from SSM at boot — nothing DB-related is hardcoded here.
    SSM_PREFIX="/${var.project_name}/${var.environment}/db"
    DB_HOST=$(aws ssm get-parameter --name "$SSM_PREFIX/host" --query 'Parameter.Value' --output text --region ${var.aws_region})
    DB_PORT=$(aws ssm get-parameter --name "$SSM_PREFIX/port" --query 'Parameter.Value' --output text --region ${var.aws_region})
    DB_NAME=$(aws ssm get-parameter --name "$SSM_PREFIX/name" --query 'Parameter.Value' --output text --region ${var.aws_region})
    DB_USER=$(aws ssm get-parameter --name "$SSM_PREFIX/username" --with-decryption --query 'Parameter.Value' --output text --region ${var.aws_region})
    DB_PASS=$(aws ssm get-parameter --name "$SSM_PREFIX/password" --with-decryption --query 'Parameter.Value' --output text --region ${var.aws_region})

    rm -rf /opt/ledger-app
    git clone --depth 1 ${local.app_repo_url} /opt/ledger-app
    cd /opt/ledger-app/app

    # NOT single-quoted here — systemd's EnvironmentFile parser has its
    # own, less predictable quoting rules than a shell (quotes can end
    # up as literal characters in the value rather than being stripped).
    # Safety instead comes from restricting the password's character
    # set at generation time (see rds.tf random_password.db_master) to
    # exclude shell/parsing metacharacters entirely, rather than trying
    # to quote around them here. See docs/incidents/incident-005.
    cat > .env <<EOT
    DATABASE_URL=postgresql://$${DB_USER}:$${DB_PASS}@$${DB_HOST}:$${DB_PORT}/$${DB_NAME}
    EOT

    python3.11 -m venv venv
    source venv/bin/activate
    pip install --upgrade pip
    pip install -r requirements.txt

    # Apply migrations before starting the app — the app assumes the
    # schema already exists, it does not create tables itself.
    alembic upgrade head

    deactivate

    # systemd unit — runs the app as a long-lived service that
    # restarts automatically on crash and starts on boot, rather than
    # a foreground process tied to this bootstrap script's lifetime.
    cat > /etc/systemd/system/ledger-app.service <<'EOT'
    [Unit]
    Description=Ledger FastAPI app
    After=network.target

    [Service]
    Type=simple
    WorkingDirectory=/opt/ledger-app/app
    EnvironmentFile=/opt/ledger-app/app/.env
    ExecStart=/opt/ledger-app/app/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000
    Restart=on-failure
    RestartSec=5

    [Install]
    WantedBy=multi-user.target
    EOT

    systemctl daemon-reload
    systemctl enable ledger-app
    systemctl start ledger-app

    echo "Bootstrap complete: ledger-app deployed and running on port 8000"
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
