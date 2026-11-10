# ALB 与 CLB 互斥。启用 ASG 时不配置 servers，成员由 ASG 单独管理。
resource "volcenginecc_alb_acl" "this" {
  count       = var.load_balancer.kind == "alb" ? 1 : 0
  acl_name    = "${var.name}-ingress"
  acl_entries = [for cidr in var.load_balancer.allowed_cidrs : { entry = cidr, description = "显式入口来源" }]
  tags        = local.tags
}
resource "volcenginecc_alb_load_balancer" "this" {
  count                      = var.load_balancer.kind == "alb" ? 1 : 0
  load_balancer_name         = var.name
  type                       = var.load_balancer.public ? "public" : "private"
  vpc_id                     = local.vpc_id
  address_ip_version         = "IPv4"
  load_balancer_edition      = "Standard"
  load_balancer_billing_type = 1
  zone_mappings              = [for key in local.zone_keys : { zone_id = var.zones[key].zone_id, subnet_id = local.subnet_ids["${key}-edge"] }]
  eip_billing_config         = var.load_balancer.public ? { isp = "BGP", billing_type = 3, bandwidth = var.load_balancer.bandwidth } : null
  delete_protection          = var.deletion_protection ? "on" : "off"
  tls_access_log = var.enable_logs ? {
    enabled  = true, project_id = volcenginecc_tls_project.this[0].project_id
    topic_id = volcenginecc_tls_topic.this["access"].topic_id
  } : null
  health_log = var.enable_logs ? {
    enabled  = true, project_id = volcenginecc_tls_project.this[0].project_id
    topic_id = volcenginecc_tls_topic.this["health"].topic_id
  } : null
  tags = local.tags
}
resource "volcenginecc_alb_server_group" "this" {
  count              = var.load_balancer.kind == "alb" ? 1 : 0
  vpc_id             = local.vpc_id
  server_group_name  = "${var.name}-web"
  server_group_type  = "instance"
  protocol           = "HTTP"
  scheduler          = "wrr"
  cross_zone_enabled = "on"
  health_check = {
    enabled   = "on", protocol = "HTTP", port = var.web_port
    interval  = 5, timeout = 3, healthy_threshold = 3, unhealthy_threshold = 3
    method    = "GET", http_version = "HTTP1.1", uri = var.load_balancer.health_path
    http_code = "http_2xx"
  }
  servers = var.autoscaling.enabled ? null : [for instance in values(local.web_instances) : {
    instance_id = instance.instance_id, type = "ecs", port = var.web_port, weight = 100
    ip          = instance.primary_network_interface.primary_ip_address
  }]
  tags = local.tags
}
resource "volcenginecc_alb_listener" "this" {
  count                      = var.load_balancer.kind == "alb" ? 1 : 0
  listener_name              = "${var.name}-web"
  load_balancer_id           = local.lb_id
  server_group_id            = local.server_group_id
  protocol                   = var.load_balancer.https ? "HTTPS" : "HTTP"
  port                       = var.load_balancer.https ? 443 : 80
  enabled                    = "on"
  certificate_source         = var.load_balancer.https ? "cert_center" : null
  cert_center_certificate_id = var.load_balancer.https ? var.load_balancer.certificate_id : null
  acl_status                 = "on"
  acl_type                   = "white"
  acl_ids                    = [volcenginecc_alb_acl.this[0].acl_id]
  tags                       = local.tags
}
resource "volcenginecc_clb_acl" "this" {
  count       = var.load_balancer.kind == "clb" ? 1 : 0
  acl_name    = "${var.name}-ingress"
  acl_entries = [for cidr in var.load_balancer.allowed_cidrs : { entry = cidr, description = "显式入口来源" }]
  tags        = local.tags
}
resource "volcenginecc_clb_clb" "this" {
  count                         = var.load_balancer.kind == "clb" ? 1 : 0
  load_balancer_name            = var.name
  load_balancer_spec            = var.load_balancer.clb_spec
  load_balancer_billing_type    = 2
  type                          = var.load_balancer.public ? "public" : "private"
  vpc_id                        = local.vpc_id
  subnet_id                     = local.subnet_ids["${local.zone_keys[0]}-edge"]
  master_zone_id                = var.zones[local.zone_keys[0]].zone_id
  slave_zone_id                 = length(local.zone_keys) > 1 ? var.zones[local.zone_keys[1]].zone_id : null
  bypass_security_group_enabled = "off"
  eip                           = var.load_balancer.public ? { isp = "BGP", bandwidth = var.load_balancer.bandwidth, eip_billing_type = 3 } : null
  # enabled/tls_enabled 是 computed-only，不能伪装为可配置日志开关。
  access_log = var.enable_logs ? {
    tls_project_id = volcenginecc_tls_project.this[0].project_id
    tls_topic_id   = volcenginecc_tls_topic.this["access"].topic_id
  } : null
  tags = local.tags
}
resource "volcenginecc_clb_server_group" "this" {
  count             = var.load_balancer.kind == "clb" ? 1 : 0
  load_balancer_id  = local.lb_id
  server_group_name = "${var.name}-web"
  type              = "instance"
  servers = var.autoscaling.enabled ? null : [for instance in values(local.web_instances) : {
    instance_id = instance.instance_id, type = "ecs", port = var.web_port, weight = 100
    ip          = instance.primary_network_interface.primary_ip_address
    description = ""
  }]
  tags = local.tags
}
resource "volcenginecc_clb_listener" "this" {
  count                      = var.load_balancer.kind == "clb" ? 1 : 0
  load_balancer_id           = local.lb_id
  server_group_id            = local.server_group_id
  listener_name              = "${var.name}-web"
  protocol                   = var.load_balancer.https ? "HTTPS" : "HTTP"
  port                       = var.load_balancer.https ? 443 : 80
  enabled                    = "on"
  certificate_source         = var.load_balancer.https ? "cert_center" : null
  cert_center_certificate_id = var.load_balancer.https ? var.load_balancer.certificate_id : null
  acl_status                 = "on"
  acl_type                   = "white"
  acl_ids                    = [volcenginecc_clb_acl.this[0].acl_id]
  # CLB 健康检查跟随后端组端口；HTTP 显式填写 8080 已实测被 API 拒绝。
  health_check = {
    enabled           = "on", interval = 5, timeout = 3
    healthy_threshold = 3, unhealthy_threshold = 3
    uri               = var.load_balancer.health_path, http_code = "http_2xx"
  }
  tags = local.tags
}
