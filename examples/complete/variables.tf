variable "deployment" {
  description = "生产环境地域、两区、预装镜像、规格、证书中心 ID、域名、Bucket 及显式入口来源。"
  type = object({
    name              = string, region = string, zone_a = string, zone_b = string
    web_image_id      = string, app_image_id = string
    web_instance_type = string, app_instance_type = string
    key_pair_name     = string, database_node_spec = string
    bucket_name       = string, allowed_cidrs = set(string)
    domain            = string, certificate_id = string
  })
}
variable "existing" {
  description = "可选已有资源。已有网络 CIDR 必须与本示例八个子网一致，其他网段请直接调用根 Module。"
  type = object({
    vpc_id      = optional(string), subnet_ids = optional(map(string), {})
    database_id = optional(string), cache_id = optional(string)
  })
  default = {}
}
variable "database_password" {
  description = "新建 RDS 密码，复用时可省略。"
  type        = string
  sensitive   = true
  default     = null
}
variable "cache_password" {
  description = "新建 Redis 密码，复用时可省略。"
  type        = string
  sensitive   = true
  default     = null
}
variable "service_egress" {
  description = "实际 DNS/TOS/TLS 端点的 CIDR、协议与端口；需具备对应私网路由。"
  type        = map(object({ cidr = string, protocol = string, port = number }))
}
variable "monitoring" {
  description = "必须提供至少一条按官方目录核实的监控规则与已配置的联系人组。"
  type = map(object({
    region              = string, namespace = string, sub_namespace = string
    metric_name         = string, metric_unit = string, threshold = string
    contact_group_ids   = set(string), statistics = optional(string, "avg")
    comparison_operator = optional(string, ">"), evaluation_count = optional(number, 3)
  }))
  validation {
    condition     = length(var.monitoring) > 0
    error_message = "complete 必须显式提供至少一条监控规则。"
  }
}
variable "tags" {
  description = "所有者与成本归属标签。"
  type        = map(string)
}
variable "load_balancer_kind" {
  description = "alb 或 clb；推荐 alb。CLB 日志启用与删除保护限制见根 README。"
  type        = string
  default     = "alb"
}
variable "clb_health_check_cidrs" {
  description = "CLB 在目标地域的官方健康检查来源 CIDR。"
  type        = set(string)
  default     = []
}
variable "deletion_protection" {
  description = "正常生产部署保持开启。"
  type        = bool
  default     = true
}
variable "allow_protection_disable" {
  description = "已确认销毁窗口允许关闭保护，先更新再销毁。"
  type        = bool
  default     = false
}
variable "cloudcontrol_endpoint" {
  description = "可选 Cloud Control API 端点；默认使用线上 Provider 的默认端点。"
  type        = string
  default     = null
}
