variable "region" {
  description = "AWS region that hosts the Lightsail instance and optional SSM activation."
  type        = string
}

variable "name" {
  description = "Base name for Lightsail and related resources."
  type        = string
}

variable "availability_zone" {
  description = "Lightsail availability zone, for example us-east-1a."
  type        = string
}

variable "bundle_id" {
  description = "Lightsail bundle/plan identifier."
  type        = string
  default     = "micro_3_0"
}

variable "blueprint_id" {
  description = "Lightsail blueprint identifier."
  type        = string
  default     = "ubuntu_24_04"
}

variable "create_static_ip" {
  description = "Attach a static IPv4 address to the instance."
  type        = bool
  default     = true
}

variable "create_ssh_key_pair" {
  description = "Create a Lightsail key pair from ssh_public_key_content."
  type        = bool
  default     = true
}

variable "ssh_key_pair_name" {
  description = "Existing or created Lightsail key pair name."
  type        = string
  default     = null
}

variable "ssh_public_key_content" {
  description = "Public key content used when create_ssh_key_pair is true."
  type        = string
  default     = null
}

variable "additional_authorized_keys" {
  description = "Extra SSH public keys appended to /home/ubuntu/.ssh/authorized_keys."
  type        = list(string)
  default     = []
}

variable "ssh_allowed_cidrs" {
  description = "IPv4 CIDRs allowed to reach the public SSH port."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ssh_allowed_ipv6_cidrs" {
  description = "IPv6 CIDRs allowed to reach the public SSH port."
  type        = list(string)
  default     = ["::/0"]
}

variable "openclaw_port" {
  description = "OpenClaw gateway port."
  type        = number
  default     = 18789
}

variable "openclaw_bind" {
  description = "Gateway bind mode used during non-interactive onboarding."
  type        = string
  default     = "loopback"

  validation {
    condition     = contains(["loopback", "lan", "tailnet", "auto", "custom"], var.openclaw_bind)
    error_message = "openclaw_bind must be one of: loopback, lan, tailnet, auto, custom."
  }
}

variable "openclaw_version" {
  description = "OpenClaw package version to install."
  type        = string
  default     = "latest"
}

variable "nodejs_major_version" {
  description = "Node.js major version installed from NodeSource."
  type        = number
  default     = 24
}

variable "gateway_token" {
  description = "Optional explicit OpenClaw gateway token. Leave null to auto-generate one."
  type        = string
  default     = null
  sensitive   = true
}

variable "openclaw_env_vars" {
  description = "Extra environment variables written to ~/.openclaw/.env. Suitable for provider API keys if you accept that they will be stored in Terraform state."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "install_aws_cli" {
  description = "Install AWS CLI v2 on the instance."
  type        = bool
  default     = true
}

variable "enable_ssm_hybrid_activation" {
  description = "Register the Lightsail instance in AWS Systems Manager using hybrid activation."
  type        = bool
  default     = true
}

variable "ssm_activation_ttl_hours" {
  description = "Lifetime of the SSM activation created for first boot registration."
  type        = number
  default     = 720
}

variable "instance_tags" {
  description = "Tags applied to the Lightsail instance."
  type        = map(string)
  default     = {}
}

variable "extra_bootstrap_commands" {
  description = "Additional shell commands appended to the bootstrap script."
  type        = string
  default     = ""
}

variable "additional_public_ports" {
  description = "Additional public firewall rules."
  type = list(object({
    from_port  = number
    to_port    = number
    protocol   = string
    cidrs      = optional(list(string), ["0.0.0.0/0"])
    ipv6_cidrs = optional(list(string), ["::/0"])
  }))
  default = []

  validation {
    condition = alltrue([
      for rule in var.additional_public_ports :
      contains(["tcp", "udp", "all"], lower(rule.protocol))
    ])
    error_message = "additional_public_ports[*].protocol must be tcp, udp, or all."
  }
}
