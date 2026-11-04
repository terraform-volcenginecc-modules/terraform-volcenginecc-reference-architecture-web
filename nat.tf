resource "volcenginecc_natgateway_ngw" "this" {
  for_each         = var.nat.enabled ? var.zones : {}
  vpc_id           = local.vpc_id
  subnet_id        = local.subnet_ids["${each.key}-edge"]
  nat_gateway_name = "${var.name}-${each.key}"
  network_type     = "internet"
  billing_type     = 3
  tags             = local.tags
  lifecycle {
    precondition {
      condition     = var.existing_vpc_id == null
      error_message = "复用 VPC 时 NAT 与已有子网路由由调用方管理，不能启用 nat.enabled。"
    }
  }
}
resource "volcenginecc_vpc_eip" "nat" {
  for_each      = var.nat.enabled ? var.zones : {}
  billing_type  = 3
  bandwidth     = var.nat.bandwidth
  isp           = "BGP"
  name          = "${var.name}-nat-${each.key}"
  instance_type = "Nat"
  instance_id   = volcenginecc_natgateway_ngw.this[each.key].nat_gateway_id
  tags          = local.tags
}
resource "volcenginecc_natgateway_snatentry" "this" {
  for_each = var.nat.enabled ? {
    for key, subnet in local.subnets : key => subnet
    if endswith(key, "-web") || endswith(key, "-app")
  } : {}
  nat_gateway_id  = volcenginecc_natgateway_ngw.this[trimsuffix(trimsuffix(each.key, "-web"), "-app")].nat_gateway_id
  eip_id          = volcenginecc_vpc_eip.nat[trimsuffix(trimsuffix(each.key, "-web"), "-app")].allocation_id
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
    next_hop_id            = volcenginecc_natgateway_ngw.this[each.key].nat_gateway_id
  }]
  tags       = local.tags
  depends_on = [volcenginecc_natgateway_snatentry.this]
}
