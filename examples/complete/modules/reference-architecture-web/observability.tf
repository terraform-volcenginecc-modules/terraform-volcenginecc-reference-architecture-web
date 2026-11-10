resource "volcenginecc_tos_bucket" "this" {
  name                  = var.bucket_name
  acl_grant             = { acl = "private" }
  storage_class         = "STANDARD"
  enable_version_status = var.environment == "prod" ? "Enabled" : null
  tags                  = local.tags
}
resource "volcenginecc_tls_project" "this" {
  count        = var.enable_logs ? 1 : 0
  project_name = "${var.name}-logs"
  tags         = local.tags
}
resource "volcenginecc_tls_topic" "this" {
  for_each    = var.enable_logs ? toset(["application", "access", "health"]) : toset([])
  project_id  = volcenginecc_tls_project.this[0].project_id
  topic_name  = "${var.name}-${each.key}"
  shard_count = 1
  ttl         = var.log_retention_days
  tags        = local.tags
}
# 指标和通知对象是地域相关依赖，使用显式输入；避免 "*" 监控整个账号。
resource "volcenginecc_cloudmonitor_rule" "this" {
  for_each          = var.monitoring
  rule_name         = "${var.name}-${each.key}"
  rule_type         = "dynamic"
  namespace         = each.value.namespace
  sub_namespace     = each.value.sub_namespace
  regions           = [each.value.region]
  enable_state      = "enable"
  level             = "warning"
  evaluation_count  = each.value.evaluation_count
  silence_time      = 5
  effect_start_at   = "00:00"
  effect_end_at     = "23:59"
  contact_group_ids = each.value.contact_group_ids
  alert_methods     = ["Email"]
  conditions = [{
    metric_name = each.value.metric_name, metric_unit = each.value.metric_unit
    statistics  = each.value.statistics, comparison_operator = each.value.comparison_operator
    threshold   = each.value.threshold
  }]
  dimension_conditions = {
    type = "tag"
    tag_condition = {
      condition = "and"
      tags      = [{ key = "Project", comparator = "equal", values = [var.name] }]
    }
  }
  recovery_notify = { enable = true }
  tags            = local.tags
}
