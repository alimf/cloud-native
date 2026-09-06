locals {
  common_tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project
    ManagedBy   = "terraform"
  })
}

module "network" {
  source = "../../../../modules/network/aws"

  cluster_name         = var.cluster_name
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  single_nat_gateway   = var.single_nat_gateway
  tags                 = local.common_tags
}

module "kubernetes" {
  source = "../../../../modules/kubernetes/aws"

  aws_region                  = var.aws_region
  cluster_name                = var.cluster_name
  kubernetes_version          = var.kubernetes_version
  calico_version              = var.calico_version
  vpc_id                      = module.network.vpc_id
  private_subnet_ids          = module.network.private_subnet_ids
  public_subnet_ids           = module.network.public_subnet_ids
  control_plane_count         = var.control_plane_count
  control_plane_instance_type = var.control_plane_instance_type
  control_plane_volume_size   = var.control_plane_volume_size
  worker_count                = var.worker_count
  worker_instance_type        = var.worker_instance_type
  worker_volume_size          = var.worker_volume_size
  pod_cidr                    = var.pod_cidr
  service_cidr                = var.service_cidr
  api_server_allowed_cidrs    = var.api_server_allowed_cidrs
  key_name                    = var.key_name
  tags                        = local.common_tags
}
