output "network" {
  description = "网络 ID 和稳定逻辑 key；已有资源仍归调用方所有。"
  value = {
    vpc_id             = local.vpc_id, subnet_ids = local.subnet_ids
    security_group_ids = { for key, sg in volcenginecc_vpc_security_group.this : key => sg.security_group_id }
  }
}
output "compute" {
  description = "静态 ECS ID 和私网接口信息；ASG 成员由云服务管理，输出 ASG ID。"
  value = {
    instances = { for key, instance in volcenginecc_ecs_instance.this : key => {
      id = instance.instance_id, network_interface = instance.primary_network_interface
    } }
    scaling_group_id = var.autoscaling.enabled ? volcenginecc_autoscaling_scaling_group.web[0].scaling_group_id : null
  }
}
output "entrypoint" {
  description = "入口 ID、域名依赖及 ALB DNS/CLB 地址；DNS 记录由调用方配置。"
  value = {
    id            = local.lb_id, server_group_id = local.server_group_id
    domain        = var.load_balancer.domain
    alb_dns_name  = var.load_balancer.kind == "alb" ? volcenginecc_alb_load_balancer.this[0].dns_name : null
    clb_public_ip = var.load_balancer.kind == "clb" ? volcenginecc_clb_clb.this[0].eip_address : null
  }
}
output "data" {
  description = "数据库/缓存 ID、新建实例私网端点；复用端点由调用方查询和配置。"
  value = {
    database_id           = local.database_id, cache_id = local.cache_id
    mysql_endpoints       = var.existing_database_id == null ? volcenginecc_rdsmysql_instance.this[0].endpoints : null
    redis_private_address = var.existing_cache_id == null ? volcenginecc_redis_instance.this[0].private_address : null
  }
}
output "storage_and_logs" {
  description = "TOS Bucket 与 TLS 项目/Topic，用于调用方配置应用和日志采集。"
  value = {
    bucket_name         = volcenginecc_tos_bucket.this.name
    tls_project_id      = var.enable_logs ? volcenginecc_tls_project.this[0].project_id : null
    topic_ids           = { for key, topic in volcenginecc_tls_topic.this : key => topic.topic_id }
    monitoring_rule_ids = { for key, rule in volcenginecc_cloudmonitor_rule.this : key => rule.id }
  }
}
output "nat" {
  description = "仅出站 NAT 网关、EIP、SNAT 与私网路由表；各逻辑可用区映射到同一高可用 NAT，不开启时为空映射。"
  value = {
    gateway_ids = var.nat.enabled ? {
      for key in keys(var.zones) : key => volcenginecc_natgateway_ngw.this[local.nat_gateway_key].nat_gateway_id
    } : {}
    eip_ids = var.nat.enabled ? {
      for key in keys(var.zones) : key => volcenginecc_vpc_eip.nat[local.nat_gateway_key].allocation_id
    } : {}
    snat_ids        = { for key, item in volcenginecc_natgateway_snatentry.this : key => item.snat_entry_id }
    route_table_ids = { for key, item in volcenginecc_vpc_route_table.private : key => item.route_table_id }
  }
}
