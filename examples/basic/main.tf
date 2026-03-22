provider "aws" {
  region = var.region
}

module "openclaw_lightsail" {
  source = "../../"

  region                 = var.region
  availability_zone      = var.availability_zone
  name                   = var.name
  ssh_public_key_content = file(var.ssh_public_key_path)
  ssh_allowed_cidrs      = var.ssh_allowed_cidrs
}

output "public_ip_address" {
  value = module.openclaw_lightsail.public_ip_address
}

output "ssh_command" {
  value = module.openclaw_lightsail.ssh_command
}
