output "instance_name" {
  description = "Lightsail instance name."
  value       = aws_lightsail_instance.this.name
}

output "public_ip_address" {
  description = "Public IPv4 address. When create_static_ip is true this is the static IP."
  value       = var.create_static_ip ? aws_lightsail_static_ip.this[0].ip_address : aws_lightsail_instance.this.public_ip_address
}

output "private_ip_address" {
  description = "Private IPv4 address."
  value       = aws_lightsail_instance.this.private_ip_address
}

output "ssh_username" {
  description = "Default SSH user for the Ubuntu blueprint."
  value       = "ubuntu"
}

output "ssh_key_pair_name" {
  description = "Lightsail SSH key pair name bound to the instance."
  value       = local.key_pair_name
}

output "ssh_command" {
  description = "SSH command template for direct shell access."
  value       = "ssh ubuntu@${var.create_static_ip ? aws_lightsail_static_ip.this[0].ip_address : aws_lightsail_instance.this.public_ip_address}"
}

output "dashboard_tunnel_command" {
  description = "SSH command template that forwards the loopback-only OpenClaw gateway to localhost."
  value       = "ssh -N -L ${var.openclaw_port}:127.0.0.1:${var.openclaw_port} ubuntu@${var.create_static_ip ? aws_lightsail_static_ip.this[0].ip_address : aws_lightsail_instance.this.public_ip_address}"
}

output "dashboard_url" {
  description = "Local URL to open after the SSH tunnel is established."
  value       = "http://127.0.0.1:${var.openclaw_port}/"
}

output "openclaw_gateway_token" {
  description = "Gateway token generated or supplied during onboarding."
  value       = local.gateway_token
  sensitive   = true
}

output "bedrock_role_arn" {
  description = "IAM role ARN used by the instance for Amazon Bedrock access."
  value       = var.enable_bedrock_access ? aws_iam_role.bedrock[0].arn : null
}

output "ssm_activation_id" {
  description = "SSM activation ID used for hybrid registration."
  value       = var.enable_ssm_hybrid_activation ? aws_ssm_activation.this[0].id : null
}
