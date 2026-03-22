# Terraform module: OpenClaw on AWS Lightsail

This repository is a reusable Terraform module that provisions an Ubuntu-based Amazon Lightsail instance, installs OpenClaw, keeps the OpenClaw gateway bound to loopback, and makes the instance reachable from your local machine over SSH. The default operating model is:

- SSH is enabled so your local coding agent can log in and install or change anything on the box.
- The OpenClaw gateway listens on `127.0.0.1:18789` by default, so the dashboard is reached through an SSH tunnel instead of a public web port.
- AWS Systems Manager hybrid activation is enabled by default as a second terminal-access path.
- Amazon Bedrock access is enabled by default by creating a role-backed AWS profile on the instance instead of writing long-lived AWS keys to disk.

## What the module creates

- A Lightsail instance running the Ubuntu 24.04 blueprint.
- An optional static IP, attached by default for a stable SSH target.
- A Lightsail SSH key pair imported from your local public key, or reuse of an existing key pair.
- OpenClaw installed globally with `npm`.
- A non-interactive OpenClaw onboarding flow that installs the gateway daemon with token auth.
- An IAM role policy that allows Bedrock model invocation, plus optional AWS Marketplace subscription permissions for first-time third-party model enablement.
- Optional SSM hybrid activation so you can also start a shell with `aws ssm start-session`.

## Usage

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

module "openclaw_lightsail" {
  source = "git::https://github.com/your-org/openclaw-aws-lightsail-terraform.git"

  region            = "us-east-1"
  availability_zone = "us-east-1a"
  name              = "openclaw-prod"

  ssh_public_key_content = file("~/.ssh/id_ed25519.pub")

  # Tighten this to your real source IPs.
  ssh_allowed_cidrs = ["203.0.113.10/32"]

  openclaw_env_vars = {
    # Optional provider env vars if you are not using Bedrock.
    ANTHROPIC_API_KEY = var.anthropic_api_key
  }
}
```

Example outputs:

```hcl
output "openclaw_ip" {
  value = module.openclaw_lightsail.public_ip_address
}

output "ssh_command" {
  value = module.openclaw_lightsail.ssh_command
}
```

## Inputs

Most important inputs:

- `region`: AWS region for Lightsail and optional SSM activation.
- `availability_zone`: Lightsail AZ, such as `us-east-1a`.
- `name`: Instance/resource base name.
- `ssh_public_key_content`: Public key content to import into Lightsail when `create_ssh_key_pair = true`.
- `ssh_allowed_cidrs`: CIDRs allowed to reach port 22.
- `openclaw_env_vars`: Environment variables written to `~/.openclaw/.env`.
- `enable_bedrock_access`: Creates the IAM role and AWS profile used for Bedrock access.
- `bedrock_resource_arns`: Restrict Bedrock calls to specific model or inference profile ARNs if you do not want `*`.
- `bedrock_allow_marketplace_access`: Keeps AWS Marketplace subscription permissions for first-time Anthropic and other third-party model activation.
- `extra_bootstrap_commands`: Extra shell commands for first boot.
- `enable_ssm_hybrid_activation`: Enables Session Manager access for a no-port shell path.

See `variables.tf` for the full interface.

## Outputs

Most useful outputs:

- `public_ip_address`
- `ssh_command`
- `dashboard_tunnel_command`
- `dashboard_url`
- `openclaw_gateway_token` (sensitive)
- `bedrock_role_arn`

See `outputs.tf` for the full list.

## Amazon Bedrock access

By default, the module creates an IAM role and writes `~/.aws/config` on the instance with a dedicated profile that uses `credential_source = Ec2InstanceMetadata`. That keeps Bedrock access keyless from the instance side and avoids storing static AWS credentials in Terraform variables or on disk.

The default policy allows:

- `bedrock:InvokeModel`
- `bedrock:InvokeModelWithResponseStream`
- `bedrock:Converse`
- `bedrock:ConverseStream`
- `bedrock:GetFoundationModel`
- `bedrock:ListFoundationModels`

If `bedrock_allow_marketplace_access = true`, the role also gets:

- `aws-marketplace:Subscribe`
- `aws-marketplace:Unsubscribe`
- `aws-marketplace:ViewSubscriptions`

This matches the practical requirement for first-time enablement of third-party Bedrock models such as Anthropic.

Security note: the module's trust policy defaults to `arn:aws:sts::<account-id>:assumed-role/AmazonLightsailInstance/*` because the Lightsail instance identity is not known early enough to use a per-instance trust policy in first-boot bootstrap. If you want a tighter trust relationship, override `bedrock_trust_principal_arn_pattern` after you know the exact instance identity you want to allow.

## How local terminal access works

### Option 1: Direct SSH

This is the path your local coding agent will usually want because it works with normal shell tooling, SCP, rsync, and port forwarding.

1. Apply Terraform.
2. Use the same private key that matches `ssh_public_key_content`.
3. Connect:

```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@$(terraform output -raw public_ip_address)
```

Programmatic examples:

```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@$(terraform output -raw public_ip_address) 'uname -a'
scp -i ~/.ssh/id_ed25519 ./local-file ubuntu@$(terraform output -raw public_ip_address):/tmp/
rsync -az -e "ssh -i ~/.ssh/id_ed25519" ./workspace/ ubuntu@$(terraform output -raw public_ip_address):/home/ubuntu/workspace/
```

### Option 2: SSH tunnel for the OpenClaw dashboard

OpenClaw stays loopback-only by default. That means you do not open the gateway port publicly; instead, forward it over SSH:

```bash
ssh -i ~/.ssh/id_ed25519 \
  -N \
  -L 18789:127.0.0.1:18789 \
  ubuntu@$(terraform output -raw public_ip_address)
```

Then open:

```text
http://127.0.0.1:18789/
```

The generated gateway token is available as a sensitive Terraform output:

```bash
terraform output -raw openclaw_gateway_token
```

### Option 3: AWS Session Manager

When `enable_ssm_hybrid_activation = true`, the module registers the Lightsail instance as an SSM managed node during first boot. Your local machine needs the AWS CLI plus the Session Manager plugin to start sessions from the terminal.

Find the managed instance ID:

```bash
aws ssm describe-instance-information \
  --region us-east-1 \
  --query 'InstanceInformationList[*].[InstanceId,SourceId]' \
  --output table
```

Start a shell:

```bash
aws ssm start-session --target mi-xxxxxxxxxxxxxxxxx --region us-east-1
```

You can also use Session Manager as an SSH transport with `ProxyCommand`, but for a local coding agent that already works well with SSH keys, direct SSH to the static IP is simpler and usually the better default.

## Post-deploy workflow

After the first `terraform apply`, the instance should already have OpenClaw installed and the gateway daemon configured. Typical next steps:

1. SSH into the box.
2. Check status:

```bash
openclaw gateway status
systemctl --user status openclaw-gateway.service
```

3. If you did not pass provider credentials in `openclaw_env_vars`, add them to `~/.openclaw/.env`.
4. Re-run configuration if needed:

```bash
openclaw configure
openclaw doctor
```

## Security notes

- Tighten `ssh_allowed_cidrs`; the default is open so the module works out of the box.
- `openclaw_env_vars` and `gateway_token` end up in Terraform state. Use them only if that is acceptable in your environment.
- If you do not need SSH, set `ssh_allowed_cidrs` to a restricted source range or prefer SSM-only access.
