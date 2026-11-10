# 每区四层子网；复用网络的所有权保留在调用方。
resource "volcenginecc_vpc_vpc" "this" {
  count      = var.existing_vpc_id == null ? 1 : 0
  vpc_name   = var.name
  cidr_block = var.vpc_cidr
  tags       = local.tags
}
resource "volcenginecc_vpc_subnet" "this" {
  for_each    = var.existing_vpc_id == null ? local.subnets : {}
  vpc_id      = local.vpc_id
  zone_id     = each.value.zone_id
  cidr_block  = each.value.cidr
  subnet_name = "${var.name}-${each.key}"
  tags        = local.tags
}
locals {
  # IPv4 地址转整数范围，校验子网包含关系及跨层/跨区重叠。
  vpc_range = [
    for host in [0, -1] : sum([for i, octet in split(".", cidrhost(var.vpc_cidr, host)) : tonumber(octet) * pow(256, 3 - i)])
  ]
  subnet_ranges = {
    for key, subnet in local.subnets : key => [
      for host in [0, -1] : sum([for i, octet in split(".", cidrhost(subnet.cidr, host)) : tonumber(octet) * pow(256, 3 - i)])
    ]
  }
  ingress = {
    web = [for cidr in local.web_sources : {
      cidr_ip = cidr, protocol = "tcp", port_start = var.web_port, port_end = var.web_port
      policy  = "accept", priority = 1, description = "入口与健康检查到 Web"
    }]
    app = [for cidr in local.tier_cidrs.web : {
      cidr_ip = cidr, protocol = "tcp", port_start = var.app_port, port_end = var.app_port
      policy  = "accept", priority = 1, description = "Web 到应用层"
    }]
  }
  egress = {
    web = [for cidr in local.tier_cidrs.app : {
      cidr_ip = cidr, protocol = "tcp", port_start = var.app_port, port_end = var.app_port
      policy  = "accept", priority = 1, description = "Web 访问应用"
    }]
    app = flatten([for port in [3306, 6379] : [for cidr in local.tier_cidrs.data : {
      cidr_ip = cidr, protocol = "tcp", port_start = port, port_end = port
      policy  = "accept", priority = 1, description = "应用访问私网数据层"
    }]])
  }
}
resource "volcenginecc_vpc_security_group" "this" {
  for_each            = toset(["web", "app"])
  vpc_id              = local.vpc_id
  security_group_name = "${var.name}-${each.key}"
  # 对齐 security-group Module 的完整规则结构，明确 Optional+Computed 字段。
  # 平台创建时会追加优先级 100 的默认出站规则，兜底拒绝确保首次创建即满足最小权限。
  ingress_permissions = [for rule in local.ingress[each.key] : merge(rule, {
    direction = "ingress", prefix_list_id = "", source_group_id = ""
  })]
  egress_permissions = [for rule in concat(local.egress[each.key], [for rule in values(var.service_egress) : {
    cidr_ip = rule.cidr, protocol = rule.protocol, port_start = rule.port, port_end = rule.port
    policy  = "accept", priority = 1, description = "显式服务端点出站"
    }], [{
    cidr_ip = "0.0.0.0/0", protocol = "all", port_start = -1, port_end = -1
    policy  = "drop", priority = 99, description = "拒绝未显式授权的出站流量"
    }]) : merge(rule, {
    direction = "egress", prefix_list_id = "", source_group_id = ""
  })]
  tags = local.tags
  # 同 VPC 的首次子网初始化完成后再配置安全组，避免原生接口操作冲突。
  depends_on = [volcenginecc_vpc_subnet.this]
  lifecycle {
    precondition {
      condition = alltrue([for r in values(local.subnet_ranges) : r[0] >= local.vpc_range[0] && r[1] <= local.vpc_range[1]]) && alltrue(flatten([
        for k1, r1 in local.subnet_ranges : [for k2, r2 in local.subnet_ranges : k1 == k2 || r1[1] < r2[0] || r2[1] < r1[0]]
      ]))
      error_message = "四层子网必须位于 VPC CIDR 内，且所有子网不得重叠。"
    }
    precondition {
      condition     = var.existing_vpc_id == null ? length(var.existing_subnet_ids) == 0 : toset(keys(var.existing_subnet_ids)) == toset(keys(local.subnets))
      error_message = "新建 VPC 禁止传已有子网；复用 VPC 必须提供全部且精确匹配的四层子网 key。"
    }
    precondition {
      condition = var.environment != "prod" || (
        length(var.zones) >= 2 && var.load_balancer.https && var.enable_logs && (var.deletion_protection || var.allow_protection_disable)
      )
      error_message = "prod 必须至少两区、HTTPS、日志与删除保护。"
    }
    precondition {
      condition     = var.environment != "prod" || !var.autoscaling.enabled || var.autoscaling.min >= length(var.zones)
      error_message = "生产 ASG 最小容量必须至少等于可用区数量。"
    }
    precondition {
      condition     = var.load_balancer.kind != "clb" || length(var.load_balancer.health_check_cidrs) > 0
      error_message = "CLB 须显式提供已核实的健康检查来源 CIDR。"
    }
    precondition {
      condition     = (var.existing_database_id != null) != (var.database != null) && (var.existing_cache_id != null) != (var.cache != null)
      error_message = "数据库与缓存必须分别二选一：创建配置或已有资源 ID。"
    }
  }
}
