provider "volcenginecc" {
  region    = var.deployment.region
  endpoints = var.cloudcontrol_endpoint == null ? null : { cloudcontrolapi = var.cloudcontrol_endpoint }
}
module "web" {
  source  = "terraform-volcenginecc-modules/reference-architecture-web/volcenginecc"
  version = "~> 1.0"

  name        = var.deployment.name
  environment = "dev"
  zones = {
    primary = {
      zone_id   = var.deployment.zone_id
      edge_cidr = "10.20.0.0/24", web_cidr = "10.20.1.0/24"
      app_cidr  = "10.20.2.0/24", data_cidr = "10.20.3.0/24"
    }
  }
  web = {
    image_id = var.deployment.web_image_id, instance_type = var.deployment.web_instance_type
  }
  app = {
    image_id = var.deployment.app_image_id, instance_type = var.deployment.app_instance_type
  }
  key_pair_name = var.deployment.key_pair_name
  nat           = { enabled = true, zone_key = "primary" }
  load_balancer = {
    kind               = "clb", public = true, https = false
    allowed_cidrs      = var.deployment.allowed_cidrs
    health_check_cidrs = ["100.64.0.0/10"]
  }
  database          = { node_spec = var.deployment.database_node_spec }
  database_password = var.database_password
  cache             = {}
  cache_password    = var.cache_password
  bucket_name       = var.deployment.bucket_name
  service_egress    = var.service_egress
  tags              = var.tags
}
