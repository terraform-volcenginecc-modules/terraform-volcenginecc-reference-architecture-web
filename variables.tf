variable "name" {
  description = "资源名称前缀，同时作为 Project 标签。"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.name))
    error_message = "name 必须为 3–31 位小写字母、数字和连字符，以字母开头。"
  }
}
variable "environment" {
  description = "dev 或 prod；prod 强制多可用区、HTTPS、备份和删除保护。"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment 必须为 dev 或 prod。"
  }
}
variable "tags" {
  description = "统一标签，建议包含 Owner、CostCenter；Project 和 Environment 由 Module 设置。"
  type        = map(string)
  default     = {}
}
variable "vpc_cidr" {
  description = "新建 VPC 的 IPv4 网段。复用时也需提供与已有 VPC 一致的网段。"
  type        = string
  default     = "10.20.0.0/16"
  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr 必须是合法 IPv4 CIDR。"
  }
}
variable "zones" {
  description = "稳定逻辑 key 对应可用区及 edge/web/app/data 四层子网；复用时 CIDR 必须反映实际网络。"
  type = map(object({
    zone_id  = string, edge_cidr = string, web_cidr = string
    app_cidr = string, data_cidr = string
  }))
  validation {
    condition = length(var.zones) > 0 && length(distinct([for z in values(var.zones) : z.zone_id])) == length(var.zones) && alltrue(flatten([
      for z in values(var.zones) : [for t in ["edge", "web", "app", "data"] : can(cidrnetmask(z["${t}_cidr"]))]
    ]))
    error_message = "zones 至少包含一个不重复的可用区，四层 CIDR 必须是合法 IPv4 网段。"
  }
}
variable "existing_vpc_id" {
  description = "复用 VPC ID；非 null 时必须同时传入全部 existing_subnet_ids，不导入或调整已有网络。"
  type        = string
  default     = null
  nullable    = true
}
variable "existing_subnet_ids" {
  description = "已有子网 ID，key 为 zones 逻辑 key 加 -edge/-web/-app/-data。"
  type        = map(string)
  default     = {}
}
variable "web" {
  description = "预装 Web 服务的镜像、实例规格、每区数量与系统盘配置；镜像必须提供健康检查路径。"
  type = object({
    image_id       = string, instance_type = string
    count_per_zone = optional(number, 1), disk_size = optional(number, 40)
    disk_type      = optional(string, "ESSD_PL0")
  })
  validation {
    condition     = var.web.count_per_zone >= 1 && var.web.count_per_zone <= 1024 && floor(var.web.count_per_zone) == var.web.count_per_zone && var.web.disk_size >= 40
    error_message = "Web 每区实例数必须为 1–1024 的整数，系统盘至少 40 GiB。"
  }
}
variable "app" {
  description = "预装应用的镜像、规格、每区数量和系统盘；应用部署与依赖配置由调用方负责。"
  type = object({
    image_id       = string, instance_type = string
    count_per_zone = optional(number, 1), disk_size = optional(number, 40)
    disk_type      = optional(string, "ESSD_PL0")
  })
  validation {
    condition     = var.app.count_per_zone >= 1 && var.app.count_per_zone <= 1024 && floor(var.app.count_per_zone) == var.app.count_per_zone && var.app.disk_size >= 40
    error_message = "应用每区实例数必须为 1–1024 的整数，系统盘至少 40 GiB。"
  }
}
variable "key_pair_name" {
  description = "已有 ECS 密钥对名称；无默认 SSH 入站规则，维护应使用私网运维通道。"
  type        = string
}
variable "web_port" {
  description = "负载均衡到 Web 的 HTTP 端口。"
  type        = number
  default     = 8080
  validation {
    condition     = var.web_port >= 1 && var.web_port <= 65535 && floor(var.web_port) == var.web_port
    error_message = "web_port 必须为 1–65535 的整数。"
  }
}
variable "app_port" {
  description = "Web 到应用层的 TCP 端口。"
  type        = number
  default     = 8080
  validation {
    condition     = var.app_port >= 1 && var.app_port <= 65535 && floor(var.app_port) == var.app_port
    error_message = "app_port 必须为 1–65535 的整数。"
  }
}
variable "load_balancer" {
  description = "入口类型、显式允许来源、HTTPS 证书依赖及健康检查；默认私网入口。CLB 须提供官方健康检查来源。"
  type = object({
    kind               = optional(string, "alb"), public = optional(bool, false)
    https              = optional(bool, false), certificate_id = optional(string)
    domain             = optional(string), allowed_cidrs = set(string)
    health_check_cidrs = optional(set(string), [])
    health_path        = optional(string, "/health"), bandwidth = optional(number, 10)
    clb_spec           = optional(string, "small_1")
  })
  validation {
    condition = contains(["alb", "clb"], var.load_balancer.kind) && length(var.load_balancer.allowed_cidrs) > 0 && alltrue([
      for c in concat(tolist(var.load_balancer.allowed_cidrs), tolist(var.load_balancer.health_check_cidrs)) : can(cidrnetmask(c))
      ]) && (!var.load_balancer.https || (
      var.load_balancer.certificate_id != null && var.load_balancer.domain != null
    )) && startswith(var.load_balancer.health_path, "/") && var.load_balancer.bandwidth >= 1
    error_message = "入口需 alb/clb、非空 IPv4 来源列表、有效健康路径；HTTPS 必须提供证书中心 ID 和域名。"
  }
}
variable "autoscaling" {
  description = "可选 Web ASG，替代静态 Web ECS；ASG 管理成员与后端注册。容量配置不自动创建指标伸缩策略。"
  type = object({
    enabled = optional(bool, false), min = optional(number, 2)
    desired = optional(number, 2), max = optional(number, 6)
  })
  default = {}
  validation {
    condition     = var.autoscaling.min >= 1 && var.autoscaling.min <= var.autoscaling.desired && var.autoscaling.desired <= var.autoscaling.max && alltrue([for n in [var.autoscaling.min, var.autoscaling.desired, var.autoscaling.max] : floor(n) == n])
    error_message = "ASG 容量须为整数且满足 1 <= min <= desired <= max。"
  }
}
variable "existing_database_id" {
  description = "已有私网 MySQL ID；Module 不修改其白名单、备份、账户或删除保护。"
  type        = string
  default     = null
}
variable "database" {
  description = "新建 RDS MySQL 配置；生产为跨区双节点，开发为单节点。规格须在目标地域可用。"
  type = object({
    node_spec     = string, engine_version = optional(string, "MySQL_8_0")
    storage_space = optional(number, 100), storage_type = optional(string, "CloudESSD_PL0")
    account_name  = optional(string, "webadmin"), backup_retention_days = optional(number, 7)
  })
  default = null
  validation {
    condition     = var.database == null ? true : var.database.storage_space >= 20 && var.database.backup_retention_days >= 7 && var.database.backup_retention_days <= 3650
    error_message = "RDS 存储至少 20 GiB，备份保留 7–3650 天。"
  }
}
variable "database_password" {
  description = "新建 RDS 超级账户密码，通过 TF_VAR 提供；敏感值仍保存在 State 中。"
  type        = string
  sensitive   = true
  default     = null
}
variable "existing_cache_id" {
  description = "已有私网 Redis ID；Module 不修改其鉴权、白名单、备份或删除保护。"
  type        = string
  default     = null
}
variable "cache" {
  description = "新建 Redis 配置；开发单节点，生产跨区主从，不启用免密访问。"
  type = object({
    engine_version = optional(string, "6.0"), shard_capacity = optional(number, 1024)
    backup_hour    = optional(number, 3)
  })
  default = null
  validation {
    condition     = var.cache == null ? true : var.cache.shard_capacity >= 256 && var.cache.backup_hour >= 0 && var.cache.backup_hour <= 23 && floor(var.cache.backup_hour) == var.cache.backup_hour
    error_message = "Redis 容量至少 256 MiB，备份小时必须是 0–23 的整数。"
  }
}
variable "cache_password" {
  description = "新建 Redis 密码，通过 TF_VAR 提供；禁止免密模式。"
  type        = string
  sensitive   = true
  default     = null
}
variable "bucket_name" {
  description = "私有 TOS Bucket 名称，必须满足地域唯一性；销毁前先清理所有版本。"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "Bucket 名称须为 3–63 位小写字母、数字和连字符。"
  }
}
variable "enable_logs" {
  description = "创建 TLS 项目和应用/入口/健康日志 Topic；prod 强制开启。应用采集 Agent 需在镜像中配置。"
  type        = bool
  default     = true
}
variable "log_retention_days" {
  description = "TLS 日志保留天数。"
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3650 && floor(var.log_retention_days) == var.log_retention_days
    error_message = "日志保留天数须为 1–3650 的整数。"
  }
}
variable "deletion_protection" {
  description = "ECS、RDS、Redis 与 ALB 删除保护；prod 强制开启，销毁前需先更新保护设置。"
  type        = bool
  default     = false
}
variable "allow_protection_disable" {
  description = "仅用于已确认的维护/销毁窗口，允许 prod 关闭删除保护；不会自动销毁任何资源。"
  type        = bool
  default     = false
}
variable "monitoring" {
  description = "CloudMonitor 指标规则；namespace/sub_namespace/metric/unit 与联系人组须按官方指标目录提供。资源通过本 Module Project 标签筛选。"
  type = map(object({
    region              = string, namespace = string, sub_namespace = string
    metric_name         = string, metric_unit = string, threshold = string
    contact_group_ids   = set(string), statistics = optional(string, "avg")
    comparison_operator = optional(string, ">"), evaluation_count = optional(number, 3)
  }))
  default = {}
  validation {
    condition     = alltrue([for r in values(var.monitoring) : length(r.contact_group_ids) > 0 && r.evaluation_count >= 1])
    error_message = "每条监控规则必须有联系人组且 evaluation_count >= 1。"
  }
}
variable "service_egress" {
  description = "显式服务出站规则，用于私网 DNS、TLS、TOS 等端点；无默认公网出站。调用方负责路由/私网端点和对应 CIDR。"
  type = map(object({
    cidr = string, protocol = string, port = number
  }))
  default = {}
  validation {
    condition = alltrue([for r in values(var.service_egress) :
      can(cidrnetmask(r.cidr)) && contains(["tcp", "udp"], r.protocol) &&
      r.port >= 1 && r.port <= 65535 && floor(r.port) == r.port
    ])
    error_message = "服务出站规则需合法 IPv4 CIDR、tcp/udp 与整数端口 1–65535。"
  }
}
variable "nat" {
  description = "可选公网 NAT：每个 VPC 一个高可用网关与出站 EIP；启用时须用 zone_key 选择稳定的承载子网。仅 Web/应用子网 SNAT，数据子网无公网默认路由，无 DNAT。复用 VPC 时须由调用方管理路由。"
  type = object({
    enabled  = optional(bool, false), bandwidth = optional(number, 10)
    zone_key = optional(string)
  })
  default = {}
  validation {
    condition     = var.nat.bandwidth >= 1 && var.nat.bandwidth <= 200 && (!var.nat.enabled || var.nat.zone_key != null)
    error_message = "NAT 出站带宽必须为 1–200 Mbps；启用 NAT 时必须提供 zone_key。"
  }
}
