#############################################
# IAM Role for the app instance/task
# Two responsibilities bundled here:
#  1. AmazonSSMManagedInstanceCore — lets SSM Session Manager reach
#     the instance without a bastion host or open port 22.
#  2. A scoped inline policy for reading only this project's SSM
#     parameters — not a blanket ssm:GetParameter/* grant.
#############################################

resource "aws_iam_role" "app" {
  name = "${var.project_name}-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-app-role"
  }
}

# Enables SSM Session Manager connectivity — this is the whole
# reason we don't need a bastion host.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Least-privilege read access to only this project's parameter path.
data "aws_iam_policy_document" "ssm_parameter_read" {
  statement {
    sid    = "ReadLedgerDbParameters"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
    ]
    resources = [
      "arn:aws:ssm:${var.aws_region}:*:parameter/${var.project_name}/${var.environment}/db/*"
    ]
  }

  # SecureString parameters are encrypted with the default aws/ssm
  # KMS key — the role needs kms:Decrypt against that key specifically,
  # not a wildcard KMS grant.
  statement {
    sid    = "DecryptSecureStringParameters"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${var.aws_region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "ssm_parameter_read" {
  name   = "${var.project_name}-ssm-parameter-read"
  policy = data.aws_iam_policy_document.ssm_parameter_read.json
}

resource "aws_iam_role_policy_attachment" "ssm_parameter_read" {
  role       = aws_iam_role.app.name
  policy_arn = aws_iam_policy.ssm_parameter_read.arn
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.project_name}-app-instance-profile"
  role = aws_iam_role.app.name
}
