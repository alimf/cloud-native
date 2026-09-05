output "api_server_endpoint" {
  description = "HTTPS endpoint of the Kubernetes API server"
  value       = "https://${aws_lb.api_server.dns_name}:6443"
}

output "api_server_nlb_dns" {
  description = "DNS name of the API server NLB"
  value       = aws_lb.api_server.dns_name
}

output "control_plane_private_ips" {
  description = "Private IPs of control plane nodes"
  value       = aws_instance.control_plane[*].private_ip
}

output "worker_private_ips" {
  description = "Private IPs of worker nodes"
  value       = aws_instance.worker[*].private_ip
}

output "control_plane_security_group_id" {
  description = "ID of the control plane security group"
  value       = aws_security_group.control_plane.id
}

output "worker_security_group_id" {
  description = "ID of the worker security group"
  value       = aws_security_group.worker.id
}

output "control_plane_instance_ids" {
  description = "EC2 instance IDs of control plane nodes"
  value       = aws_instance.control_plane[*].id
}

output "worker_instance_ids" {
  description = "EC2 instance IDs of worker nodes"
  value       = aws_instance.worker[*].id
}

output "ssm_join_command_path" {
  description = "SSM Parameter Store path that holds the kubeadm worker join command"
  value       = local.ssm_join_command_path
}
