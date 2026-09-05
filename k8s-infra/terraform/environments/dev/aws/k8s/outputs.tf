output "api_server_endpoint" {
  description = "HTTPS endpoint of the Kubernetes API server"
  value       = module.kubernetes.api_server_endpoint
}

output "control_plane_private_ips" {
  description = "Private IPs of control plane nodes"
  value       = module.kubernetes.control_plane_private_ips
}

output "worker_private_ips" {
  description = "Private IPs of worker nodes"
  value       = module.kubernetes.worker_private_ips
}

output "ssm_join_command_path" {
  description = "SSM parameter path holding the kubeadm worker join command"
  value       = module.kubernetes.ssm_join_command_path
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.network.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.network.private_subnet_ids
}

output "retrieve_kubeconfig" {
  description = "SSM command to download the kubeconfig from the control plane"
  value       = "aws ssm start-session --target ${module.kubernetes.control_plane_instance_ids[0]} --region ${var.aws_region}"
}
