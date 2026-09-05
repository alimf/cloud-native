variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod)"
  type        = string
}

variable "project" {
  description = "Project name used in resource tags"
  type        = string
}

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

# ── Network ───────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "availability_zones" {
  description = "Availability zones to deploy subnets into"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "Share a single NAT gateway across AZs (cost-saving for non-production)"
  type        = bool
  default     = true
}

# ── Cluster compute ───────────────────────────────────────────

variable "control_plane_count" {
  description = "Number of control plane nodes (1 for basic, 3 for HA)"
  type        = number
  default     = 1
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
  description = "CIDR for Kubernetes pods (must not overlap with VPC CIDR)"
  type        = string
  default     = "192.168.0.0/16"
}

variable "service_cidr" {
  description = "CIDR for Kubernetes services"
  type        = string
  default     = "10.96.0.0/12"
}

variable "api_server_allowed_cidrs" {
  description = "CIDRs allowed to reach the Kubernetes API server on port 6443"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "key_name" {
  description = "EC2 key pair for SSH access (optional; use SSM Session Manager as the default)"
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags to merge into all resources"
  type        = map(string)
  default     = {}
}
