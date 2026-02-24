output "n8n_url" {
  description = "Public URL for the n8n instance."
  value       = "https://${local.fqdn}"
}

output "instance_public_ip" {
  description = "Elastic IP assigned to the EC2 instance."
  value       = aws_eip.n8n.public_ip
}

output "instance_id" {
  description = "EC2 Instance ID (useful for SSM Session Manager)."
  value       = aws_instance.n8n.id
}

output "data_volume_id" {
  description = "ID del volumen EBS que almacena los datos persistentes de n8n (/opt/n8n)."
  value       = [for b in aws_instance.n8n.ebs_block_device : b.volume_id][0]
}
