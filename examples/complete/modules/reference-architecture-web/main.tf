# 可组合的 Web 架构 Module。Provider、认证与 State 由调用方管理。
locals {
  tags = [for key, value in merge(var.tags, {
    Project = var.name, Environment = var.environment
  }) : { key = key, value = value }]
  zone_keys = sort(keys(var.zones))
  subnets = merge([
    for key, zone in var.zones : {
      for tier in ["edge", "web", "app", "data"] : "${key}-${tier}" => {
        zone_id = zone.zone_id
        cidr    = zone["${tier}_cidr"]
      }
    }
  ]...)
  vpc_id = var.existing_vpc_id != null ? var.existing_vpc_id : volcenginecc_vpc_vpc.this[0].vpc_id
  subnet_ids = {
    for key, subnet in local.subnets : key => (
      var.existing_vpc_id != null ? var.existing_subnet_ids[key] : volcenginecc_vpc_subnet.this[key].subnet_id
    )
  }
  tier_cidrs = {
    for tier in ["edge", "web", "app", "data"] : tier => [
      for zone in values(var.zones) : zone["${tier}_cidr"]
    ]
  }
  # HTTP/HTTPS ALB/CLB 的转发与健康检查来源均为官方服务网段。
  # https://www.volcengine.com/docs/6767/145613
  # https://www.volcengine.com/docs/6406/69033
  web_sources = ["100.64.0.0/10"]
  compute_instances = merge([
    for zone_key, zone in var.zones : merge(
      var.autoscaling.enabled ? {} : {
        for index in range(var.web.count_per_zone) : "web-${zone_key}-${index}" => {
          tier      = "web", zone_key = zone_key, zone_id = zone.zone_id
          image_id  = var.web.image_id, instance_type = var.web.instance_type
          disk_size = var.web.disk_size, disk_type = var.web.disk_type
        }
      },
      {
        for index in range(var.app.count_per_zone) : "app-${zone_key}-${index}" => {
          tier      = "app", zone_key = zone_key, zone_id = zone.zone_id
          image_id  = var.app.image_id, instance_type = var.app.instance_type
          disk_size = var.app.disk_size, disk_type = var.app.disk_type
        }
      }
    )
  ]...)
  web_instances = { for key, instance in volcenginecc_ecs_instance.this : key => instance if startswith(key, "web-") }
  database_id   = var.existing_database_id != null ? var.existing_database_id : volcenginecc_rdsmysql_instance.this[0].instance_id
  cache_id      = var.existing_cache_id != null ? var.existing_cache_id : volcenginecc_redis_instance.this[0].instance_id
  lb_id         = var.load_balancer.kind == "alb" ? volcenginecc_alb_load_balancer.this[0].load_balancer_id : volcenginecc_clb_clb.this[0].load_balancer_id
  server_group_id = var.load_balancer.kind == "alb" ? (
    volcenginecc_alb_server_group.this[0].server_group_id
  ) : volcenginecc_clb_server_group.this[0].server_group_id
}
