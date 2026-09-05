variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version to install (e.g. 1.31.0)"
  type        = string
  default     = "1.31.0"
}

variable "calico_version" {
  description = "Calico CNI version to install"
  type        = string
  default     = "3.29.0"
}

variable "vpc_id" {
  description = "ID of the VPC to deploy cluster nodes into"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for control plane and worker nodes"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for the API server NLB"
  type        = list(string)
}

variable "control_plane_count" {
  description = "Number of control plane nodes (must be odd: 1 for basic, 3 for HA etcd quorum)"
  type        = number
  default     = 1

  validation {
    condition     = var.control_plane_count % 2 == 1
    error_message = "control_plane_count must be an odd number (1, 3, 5...)."
  }
}

variable "control_plane_instance_type" {
  description = "EC2 instance type for control plane nodes"
  type        = string
  default     = "t3.medium"
}

variable "control_plane_volume_size" {
  description = "Root EBS volume size (GiB) for control plane nodes"
  type        = number
  default     = 50
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
}

variable "worker_instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "worker_volume_size" {
  description = "Root EBS volume size (GiB) for worker nodes"
  type        = number
  default     = 30
}

variable "pod_cidr" {
  description = "CIDR block for Kubernetes pods (must not overlap VPC CIDR)"
  type        = string
  default     = "192.168.0.0/16"
}

variable "service_cidr" {
  description = "CIDR block for Kubernetes services"
  type        = string
  default     = "10.96.0.0/12"
}

variable "api_server_allowed_cidrs" {
  description = "CIDR blocks allowed to reach the Kubernetes API server (port 6443)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "key_name" {
  description = "EC2 key pair name for SSH access (optional; prefer SSM Session Manager)"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
