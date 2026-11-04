variable "deployment" {
  description = "地域相关依赖，镜像需预装 Web/应用与日志采集，ID 和规格请从目标账号获得。"
  type = object({
    name              = string, region = string, zone_id = string
    web_image_id      = string, app_image_id = string
    web_instance_type = string, app_instance_type = string
    key_pair_name     = string, database_node_spec = string
    bucket_name       = string, allowed_cidrs = set(string)
  })
}
variable "database_password" {
  description = "RDS 密码，通过 TF_VAR_database_password 提供。"
  type        = string
  sensitive   = true
}
variable "cache_password" {
  description = "Redis 密码，通过 TF_VAR_cache_password 提供。"
  type        = string
  sensitive   = true
}
variable "service_egress" {
  description = "目标环境 DNS/TOS/TLS 私网服务端点出站规则，具体来源见根 README。"
  type        = map(object({ cidr = string, protocol = string, port = number }))
}
variable "tags" {
  description = "Owner/CostCenter 等标签。"
  type        = map(string)
  default     = {}
}
variable "cloudcontrol_endpoint" {
  description = "可选 Cloud Control API 端点；默认使用线上 Provider 的默认端点。"
  type        = string
  default     = null
}
