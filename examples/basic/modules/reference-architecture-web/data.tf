# 白名单先创建，再由实例引用，避免双重管理关联或创建循环。
resource "volcenginecc_rdsmysql_allow_list" "this" {
  count           = var.existing_database_id == null ? 1 : 0
  allow_list_name = "${var.name}-app"
  allow_list_type = "IPv4"
  allow_list      = toset(local.tier_cidrs.app)
}
resource "volcenginecc_rdsmysql_instance" "this" {
  count             = var.existing_database_id == null ? 1 : 0
  instance_name     = "${var.name}-mysql"
  vpc_id            = local.vpc_id
  subnet_id         = local.subnet_ids["${local.zone_keys[0]}-data"]
  db_engine_version = var.database.engine_version
  instance_type     = var.environment == "prod" ? "DoubleNode" : "SingleNode"
  nodes = concat([{
    node_type = "Primary", node_spec = var.database.node_spec
    zone_id   = var.zones[local.zone_keys[0]].zone_id
    }], var.environment == "prod" ? [{
    node_type = "Secondary", node_spec = var.database.node_spec
    zone_id   = var.zones[local.zone_keys[1]].zone_id
  }] : [])
  storage_space          = var.database.storage_space
  storage_type           = var.database.storage_type
  super_account_name     = var.database.account_name
  super_account_password = var.database_password
  port                   = 3306
  charge_detail          = { charge_type = "PostPaid" }
  deletion_protection    = var.deletion_protection ? "Enabled" : "Disabled"
  allow_list_ids         = [volcenginecc_rdsmysql_allow_list.this[0].allow_list_id]
  backup_policy = {
    backup_policy_base = {
      data_backup_retention_day = var.database.backup_retention_days
      data_full_backup_periods  = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
      data_full_backup_time     = "18:00Z-19:00Z"
      public_download_enable    = false
    }
  }
  tags = local.tags
  lifecycle {
    precondition {
      condition     = var.database_password != null
      error_message = "创建 RDS 必须通过敏感变量提供 database_password。"
    }
  }
}
resource "volcenginecc_redis_allow_list" "this" {
  count           = var.existing_cache_id == null ? 1 : 0
  allow_list_name = "${var.name}-app"
  allow_list      = join(",", local.tier_cidrs.app)
}
resource "volcenginecc_redis_instance" "this" {
  count               = var.existing_cache_id == null ? 1 : 0
  instance_name       = "${var.name}-redis"
  vpc_id              = local.vpc_id
  subnet_id           = local.subnet_ids["${local.zone_keys[0]}-data"]
  engine_version      = var.cache.engine_version
  shard_capacity      = var.cache.shard_capacity
  sharded_cluster     = 0
  node_number         = var.environment == "prod" ? 2 : 1
  multi_az            = var.environment == "prod" ? "enabled" : "disabled"
  configure_nodes     = [for key in slice(local.zone_keys, 0, var.environment == "prod" ? 2 : 1) : { az = var.zones[key].zone_id }]
  charge_type         = "PostPaid"
  no_auth_mode        = "close"
  password            = var.cache_password
  port                = 6379
  deletion_protection = var.deletion_protection ? "enabled" : "disabled"
  allow_list_ids      = [volcenginecc_redis_allow_list.this[0].allow_list_id]
  # Standalone 不支持备份；仅生产主从实例配置备份。
  backup_plan = var.environment == "prod" ? {
    active = true, backup_hour = var.cache.backup_hour, period = [1, 2, 3, 4, 5, 6, 7]
  } : null
  tags = local.tags
  lifecycle {
    precondition {
      condition     = var.cache_password != null
      error_message = "创建 Redis 必须通过敏感变量提供 cache_password。"
    }
  }
}
