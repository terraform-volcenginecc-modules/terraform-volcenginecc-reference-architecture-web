provider "volcenginecc" {
  region    = var.deployment.region
  endpoints = var.cloudcontrol_endpoint == null ? null : { cloudcontrolapi = var.cloudcontrol_endpoint }
}
module "web" {
  source = "terraform-volcenginecc-modules/reference-architecture-web/volcenginecc"

  name        = var.deployment.name
  environment = "prod"
  zones = {
    primary = {
      zone_id   = var.deployment.zone_a
      edge_cidr = "10.20.0.0/24", web_cidr = "10.20.1.0/24"
      app_cidr  = "10.20.2.0/24", data_cidr = "10.20.3.0/24"
    }
    secondary = {
      zone_id   = var.deployment.zone_b
      edge_cidr = "10.20.4.0/24", web_cidr = "10.20.5.0/24"
      app_cidr  = "10.20.6.0/24", data_cidr = "10.20.7.0/24"
    }
  }
  web = {
    image_id       = var.deployment.web_image_id, instance_type = var.deployment.web_instance_type
    count_per_zone = 1
  }
  app = {
    image_id = var.deployment.app_image_id, instance_type = var.deployment.app_instance_type
  }
  key_pair_name = var.deployment.key_pair_name
  nat           = { enabled = var.existing.vpc_id == null, zone_key = "primary" }
  autoscaling   = { enabled = false }
  load_balancer = {
    kind               = var.load_balancer_kind, public = true, https = true
    domain             = var.deployment.domain, certificate_id = var.deployment.certificate_id
    allowed_cidrs      = var.deployment.allowed_cidrs
    health_check_cidrs = var.clb_health_check_cidrs
  }
  existing_vpc_id      = var.existing.vpc_id
  existing_subnet_ids  = var.existing.subnet_ids
  existing_database_id = var.existing.database_id
  database = var.existing.database_id == null ? {
    node_spec = var.deployment.database_node_spec, backup_retention_days = 30
  } : null
  database_password        = var.database_password
  existing_cache_id        = var.existing.cache_id
  cache                    = var.existing.cache_id == null ? {} : null
  cache_password           = var.cache_password
  bucket_name              = var.deployment.bucket_name
  enable_logs              = true
  log_retention_days       = 90
  deletion_protection      = var.deletion_protection || !var.allow_protection_disable
  allow_protection_disable = var.allow_protection_disable
  service_egress           = var.service_egress
  monitoring               = var.monitoring
  tags                     = var.tags
}
