locals {
  nat_gateway_zone_key = var.nat.enabled ? var.nat.zone_key : null
  nat_gateway_keys     = var.nat.enabled ? toset(["egress"]) : toset([])
  nat_gateway_key      = "egress"
}

resource "volcenginecc_natgateway_ngw" "this" {
  for_each         = local.nat_gateway_keys
  vpc_id           = local.vpc_id
  subnet_id        = local.subnet_ids["${local.nat_gateway_zone_key}-edge"]
  nat_gateway_name = "${var.name}-egress"
  network_type     = "internet"
  billing_type     = 3
  description      = "跨可用区私网子网共用的高可用公网出口"
  tags             = local.tags
  lifecycle {
    precondition {
      condition     = var.existing_vpc_id == null
      error_message = "复用 VPC 时 NAT 与已有子网路由由调用方管理，不能启用 nat.enabled。"
    }
    precondition {
      condition     = contains(keys(var.zones), local.nat_gateway_zone_key)
      error_message = "nat.zone_key 必须匹配 zones 中的稳定逻辑 key。"
    }
  }
}
resource "volcenginecc_vpc_eip" "nat" {
  for_each      = local.nat_gateway_keys
  billing_type  = 3
  bandwidth     = var.nat.bandwidth
  isp           = "BGP"
  name          = "${var.name}-nat-egress"
  instance_type = "Nat"
  instance_id   = volcenginecc_natgateway_ngw.this[each.key].nat_gateway_id
  tags          = local.tags
}
resource "volcenginecc_natgateway_snatentry" "this" {
  for_each = var.nat.enabled ? {
    for key, subnet in local.subnets : key => subnet
    if endswith(key, "-web") || endswith(key, "-app")
  } : {}
  nat_gateway_id  = volcenginecc_natgateway_ngw.this[local.nat_gateway_key].nat_gateway_id
  eip_id          = volcenginecc_vpc_eip.nat[local.nat_gateway_key].allocation_id
  subnet_id       = local.subnet_ids[each.key]
  snat_entry_name = "${var.name}-${each.key}"
}
resource "volcenginecc_vpc_route_table" "private" {
  for_each         = var.nat.enabled ? var.zones : {}
  vpc_id           = local.vpc_id
  route_table_name = "${var.name}-private-${each.key}"
  associate_type   = "Subnet"
  subnet_ids       = [local.subnet_ids["${each.key}-web"], local.subnet_ids["${each.key}-app"]]
  custom_route_entries = [{
    destination_cidr_block = "0.0.0.0/0"
    next_hop_type          = "NatGW"
    next_hop_id            = volcenginecc_natgateway_ngw.this[local.nat_gateway_key].nat_gateway_id
  }]
  tags       = local.tags
  depends_on = [volcenginecc_natgateway_snatentry.this]
}
