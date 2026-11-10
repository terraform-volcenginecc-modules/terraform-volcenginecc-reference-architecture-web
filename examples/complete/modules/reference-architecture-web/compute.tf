# 预装镜像承载应用，不通过 provisioner 下载或执行外部脚本。
resource "volcenginecc_ecs_instance" "this" {
  for_each             = local.compute_instances
  instance_name        = "${var.name}-${each.key}"
  zone_id              = each.value.zone_id
  instance_type        = each.value.instance_type
  instance_charge_type = "PostPaid"
  image                = { image_id = each.value.image_id }
  key_pair             = { key_pair_name = var.key_pair_name }
  system_volume = {
    size                 = each.value.disk_size, volume_type = each.value.disk_type
    delete_with_instance = true
  }
  primary_network_interface = {
    vpc_id             = local.vpc_id
    subnet_id          = local.subnet_ids["${each.value.zone_key}-${each.value.tier}"]
    security_group_ids = [volcenginecc_vpc_security_group.this[each.value.tier].security_group_id]
  }
  deletion_protection = var.deletion_protection
  tags                = local.tags
}
resource "volcenginecc_ecs_launch_template" "web" {
  count                = var.autoscaling.enabled ? 1 : 0
  launch_template_name = "${var.name}-web"
  launch_template_tags = local.tags
  launch_template_version = {
    image_id             = var.web.image_id, instance_type_id = var.web.instance_type
    instance_charge_type = "PostPaid", instance_name = "${var.name}-web"
    key_pair_name        = var.key_pair_name, vpc_id = local.vpc_id
    network_interfaces = [{
      security_group_ids = [volcenginecc_vpc_security_group.this["web"].security_group_id]
    }]
    volumes = [{
      size = var.web.disk_size, volume_type = var.web.disk_type, delete_with_instance = true
    }]
    tags = local.tags
  }
}
resource "volcenginecc_autoscaling_scaling_group" "web" {
  count                   = var.autoscaling.enabled ? 1 : 0
  scaling_group_name      = "${var.name}-web"
  subnet_ids              = [for key in local.zone_keys : local.subnet_ids["${key}-web"]]
  launch_template_id      = volcenginecc_ecs_launch_template.web[0].launch_template_id
  launch_template_version = tostring(volcenginecc_ecs_launch_template.web[0].latest_version_number)
  min_instance_number     = var.autoscaling.min
  desire_instance_number  = var.autoscaling.desired
  max_instance_number     = var.autoscaling.max
  multi_az_policy         = "BALANCE"
  health_check_type       = "ECS"
  is_enable_scaling_group = true
  scaling_mode            = "release"
  server_group_attributes = [{
    server_group_id = local.server_group_id
    type            = upper(var.load_balancer.kind), port = var.web_port, weight = 100
  }]
  tags = local.tags
}
