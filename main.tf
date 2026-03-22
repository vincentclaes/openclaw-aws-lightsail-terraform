locals {
  key_pair_name = var.create_ssh_key_pair ? aws_lightsail_key_pair.this[0].name : var.ssh_key_pair_name
  gateway_token = coalesce(var.gateway_token, random_password.gateway_token.result)

  bootstrap_env_lines = concat(
    ["OPENCLAW_GATEWAY_TOKEN=${local.gateway_token}"],
    [for key, value in nonsensitive(var.openclaw_env_vars) : "${key}=${value}"]
  )

  bootstrap_script = templatefile("${path.module}/startup/bootstrap.sh.tftpl", {
    nodejs_major_version       = var.nodejs_major_version
    openclaw_version           = var.openclaw_version
    openclaw_port              = var.openclaw_port
    openclaw_bind              = var.openclaw_bind
    install_aws_cli            = var.install_aws_cli
    additional_authorized_keys = join("\n", var.additional_authorized_keys)
    bootstrap_env_content      = join("\n", local.bootstrap_env_lines)
    ssm_enabled                = var.enable_ssm_hybrid_activation
    ssm_activation_id          = var.enable_ssm_hybrid_activation ? aws_ssm_activation.this[0].id : ""
    ssm_activation_code        = var.enable_ssm_hybrid_activation ? aws_ssm_activation.this[0].activation_code : ""
    region                     = var.region
    extra_bootstrap_commands   = trimspace(var.extra_bootstrap_commands)
  })

  public_ports = concat(
    [
      {
        from_port  = 22
        to_port    = 22
        protocol   = "tcp"
        cidrs      = var.ssh_allowed_cidrs
        ipv6_cidrs = var.ssh_allowed_ipv6_cidrs
      }
    ],
    [
      for rule in var.additional_public_ports : {
        from_port  = rule.from_port
        to_port    = rule.to_port
        protocol   = lower(rule.protocol)
        cidrs      = rule.cidrs
        ipv6_cidrs = rule.ipv6_cidrs
      }
    ]
  )
}

resource "random_password" "gateway_token" {
  length  = 40
  special = false
}

resource "aws_lightsail_key_pair" "this" {
  count      = var.create_ssh_key_pair ? 1 : 0
  name       = coalesce(var.ssh_key_pair_name, "${var.name}-ssh")
  public_key = var.ssh_public_key_content
}

resource "aws_iam_role" "ssm" {
  count = var.enable_ssm_hybrid_activation ? 1 : 0
  name  = "${var.name}-ssm-hybrid"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ssm.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  count      = var.enable_ssm_hybrid_activation ? 1 : 0
  role       = aws_iam_role.ssm[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_ssm_activation" "this" {
  count              = var.enable_ssm_hybrid_activation ? 1 : 0
  name               = "${var.name}-activation"
  iam_role           = aws_iam_role.ssm[0].name
  registration_limit = 1
  expiration_date    = timeadd(timestamp(), "${var.ssm_activation_ttl_hours}h")

  lifecycle {
    ignore_changes = [expiration_date]
  }

  depends_on = [aws_iam_role_policy_attachment.ssm_core]
}

resource "aws_lightsail_instance" "this" {
  name              = var.name
  availability_zone = var.availability_zone
  blueprint_id      = var.blueprint_id
  bundle_id         = var.bundle_id
  key_pair_name     = local.key_pair_name
  user_data         = local.bootstrap_script
  tags              = var.instance_tags

  lifecycle {
    ignore_changes = [user_data]

    precondition {
      condition     = var.create_ssh_key_pair ? var.ssh_public_key_content != null && trimspace(var.ssh_public_key_content) != "" : true
      error_message = "ssh_public_key_content must be set when create_ssh_key_pair is true."
    }

    precondition {
      condition     = var.create_ssh_key_pair ? true : var.ssh_key_pair_name != null && trimspace(var.ssh_key_pair_name) != ""
      error_message = "ssh_key_pair_name must be set when create_ssh_key_pair is false."
    }
  }
}

resource "aws_lightsail_static_ip" "this" {
  count = var.create_static_ip ? 1 : 0
  name  = "${var.name}-ip"
}

resource "aws_lightsail_static_ip_attachment" "this" {
  count          = var.create_static_ip ? 1 : 0
  static_ip_name = aws_lightsail_static_ip.this[0].name
  instance_name  = aws_lightsail_instance.this.name
}

resource "aws_lightsail_instance_public_ports" "this" {
  instance_name = aws_lightsail_instance.this.name

  dynamic "port_info" {
    for_each = local.public_ports

    content {
      from_port  = port_info.value.from_port
      to_port    = port_info.value.to_port
      protocol   = port_info.value.protocol
      cidrs      = port_info.value.cidrs
      ipv6_cidrs = port_info.value.ipv6_cidrs
    }
  }
}

resource "terraform_data" "ssm_deregister" {
  count = var.enable_ssm_hybrid_activation ? 1 : 0

  input = {
    activation_id = aws_ssm_activation.this[0].id
    region        = var.region
  }

  depends_on = [
    aws_lightsail_instance.this,
    aws_ssm_activation.this,
  ]

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      for id in $(aws ssm describe-instance-information \
        --region "${self.input.region}" \
        --filters "Key=ActivationIds,Values=${self.input.activation_id}" \
        --query "InstanceInformationList[*].InstanceId" \
        --output text 2>/dev/null); do
        aws ssm deregister-managed-instance \
          --region "${self.input.region}" \
          --instance-id "$id" 2>/dev/null || true
      done
    EOT
  }
}
