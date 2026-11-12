# terraform-volcenginecc-reference-architecture-web

火山引擎三层 Web 基础设施模块，统一配置网络、计算、入口、数据、存储与日志。

## 1. 概述（Overview）

模块支持单区开发和多区生产环境，每区划分 edge、web、app、data 四层子网，按负载均衡 → Web → App → 私网 MySQL/Redis 的关系配置资源，配套 TOS、TLS 和可选监控、Web ASG、NAT。公网入站仅通过负载均衡，ECS 不绑定公网 EIP；NAT 仅为 Web/App 配置 SNAT。已有网络和数据资源可通过 ID 复用，仍由调用方维护；应用安装、DNS、证书及日志采集配置由调用方完成。

## 2. 用法（Usage）

准备目标地域的可用区、已预装 Web/App 服务的镜像、ECS 与 MySQL 规格、已有密钥对和地域唯一的 Bucket 名称。Web 服务应监听 `8080` 并提供 `/health`；App 应监听 `8080`。入口来源填实际访问者的公网出口 CIDR，服务出站填实际 DNS/TOS/TLS 等端点的 CIDR、协议和端口，并确认对应路由、权限、服务开通状态与配额。

以下是本地调用配置：在完整仓库的隔离副本 `examples/basic` 中使用，其中 `source = "../.."` 指向副本根模块。用以下完整配置替换副本该目录原有的调用方 `.tf` 配置，避免重复声明变量或 Provider。本段展示私网 HTTP ALB 的最小调用；仓库已有 basic 示例采用公网 HTTP CLB，不能将两者的入口参数混用。

```hcl
terraform {
  required_version = ">= 1.5.7, < 1.12.0"
  required_providers {
    volcenginecc = {
      source  = "volcengine/volcenginecc"
      version = "= 0.0.73"
    }
  }
}

variable "deployment" {
  type = object({
    name = string, region = string, zone_id = string
    web_image_id = string, app_image_id = string
    web_instance_type = string, app_instance_type = string
    key_pair_name = string, database_node_spec = string
    bucket_name = string, allowed_cidrs = set(string)
  })
}
variable "database_password" {
  type      = string
  sensitive = true
}
variable "cache_password" {
  type      = string
  sensitive = true
}
variable "service_egress" {
  type = map(object({ cidr = string, protocol = string, port = number }))
}

provider "volcenginecc" {
  region = var.deployment.region
}

module "web" {
  source  = "terraform-volcenginecc-modules/reference-architecture-web/volcenginecc"
  version = "~> 1.0"

  name = var.deployment.name
  zones = {
    primary = {
      zone_id = var.deployment.zone_id
      edge_cidr = "10.20.0.0/24", web_cidr = "10.20.1.0/24"
      app_cidr = "10.20.2.0/24", data_cidr = "10.20.3.0/24"
    }
  }
  web = {
    image_id = var.deployment.web_image_id, instance_type = var.deployment.web_instance_type
  }
  app = {
    image_id = var.deployment.app_image_id, instance_type = var.deployment.app_instance_type
  }
  key_pair_name     = var.deployment.key_pair_name
  load_balancer     = { allowed_cidrs = var.deployment.allowed_cidrs }
  database          = { node_spec = var.deployment.database_node_spec }
  database_password = var.database_password
  cache             = {}
  cache_password    = var.cache_password
  bucket_name       = var.deployment.bucket_name
  service_egress    = var.service_egress
}
```

调用方通过 Provider 支持的 `VOLCENGINE_ACCESS_KEY`、`VOLCENGINE_SECRET_KEY` 注入凭据，通过 `TF_VAR_database_password`、`TF_VAR_cache_password` 或平台敏感变量注入密码。在隔离副本运行 Terraform `1.5.7`，准备该配置所需的 `terraform.tfvars` 和独立 State/backend；真实参数与密码不写入 README 或 Git。

```bash
terraform init
terraform plan -out=部署计划.tfplan
terraform apply 部署计划.tfplan
terraform output -json
```

Apply 后用计算与数据端点配置 Web 代理、应用数据库和缓存连接，再配置 TOS 访问、日志采集及需要的 DNS。检查入口、Web → App → MySQL/Redis、隔离和显式出站；最后检查幂等：

```bash
terraform plan
```

预期为 `No changes`。销毁前清空 Bucket 的对象、历史版本和删除标记；若启用了保护，先按第 9 节关闭并核对实际保护状态，再执行：

```bash
terraform destroy
```

仓库两套 example 的实际 `source` 保留为 `terraform-volcenginecc-modules/reference-architecture-web/volcenginecc`。该 Registry 地址需正式发布后才能安装，本次未核实发布状态或可用版本。本地测试使用完整仓库的隔离副本，仅在副本的 example 中改用 `../..`，不为本地 source 设置 `version`。

## 3. 示例（Examples）

- `examples/basic`：单区开发环境，四个子网、一台 Web 和一台 App、公网 HTTP CLB、一个 NAT、私网单节点 MySQL/Redis、TOS 和 TLS。需要地域依赖、两项密码、入口白名单与服务出站规则。

- `examples/complete`：双区生产配置，八个子网、两台静态 Web 和两台 App、公网 HTTPS ALB、一个共享 NAT、跨区 MySQL/Redis、90 天 TLS、30 天 MySQL 备份及至少一条监控规则。额外准备证书、域名、联系人组和归属标签；可复用网络及数据资源，也可选择 CLB。已有网络的路由与 NAT 由调用方维护。

两套示例均关闭 ASG。完整新建且 complete 仅配置一条监控规则时，预期分别管理 27、37 项资源；实际数量随复用条件和监控条数变化，不包含云服务隐式创建的资源。

## 4. 版本要求（Requirements）

| 名称 | 版本 |
|---|---|
| Terraform | 源码约束 `>= 1.5.7, < 1.12.0`；项目固定基线 `= 1.5.7` |
| `volcengine/volcenginecc` | 根模块 `>= 0.0.73`；两套 example 固定 `= 0.0.73` |

源码允许的引擎范围比固定基线宽；本次文档更新保留实际约束，未调整版本文件。地域相关规格、证书、服务权限与配额由调用方核实。

## 5. Providers（Providers）

| 名称 | 来源 |
|---|---|
| `volcenginecc` | `volcengine/volcenginecc` |

根模块只声明 Provider 依赖，不配置地域、凭据或 alias；配置由调用方提供。Provider 文档见 [Registry](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs)。

## 6. 资源（Resources）

| 模式 | 类型 | 名称 |
|---|---|---|
| 创建 | `volcenginecc_vpc_vpc` | `volcenginecc_vpc_vpc.this` |
| 创建 | `volcenginecc_vpc_subnet` | `volcenginecc_vpc_subnet.this` |
| 创建 | `volcenginecc_vpc_security_group` | `volcenginecc_vpc_security_group.this` |
| 创建 | `volcenginecc_ecs_instance` | `volcenginecc_ecs_instance.this` |
| 创建 | `volcenginecc_ecs_launch_template` | `volcenginecc_ecs_launch_template.web` |
| 创建 | `volcenginecc_autoscaling_scaling_group` | `volcenginecc_autoscaling_scaling_group.web` |
| 创建 | `volcenginecc_alb_acl` | `volcenginecc_alb_acl.this` |
| 创建 | `volcenginecc_alb_load_balancer` | `volcenginecc_alb_load_balancer.this` |
| 创建 | `volcenginecc_alb_server_group` | `volcenginecc_alb_server_group.this` |
| 创建 | `volcenginecc_alb_listener` | `volcenginecc_alb_listener.this` |
| 创建 | `volcenginecc_clb_acl` | `volcenginecc_clb_acl.this` |
| 创建 | `volcenginecc_clb_clb` | `volcenginecc_clb_clb.this` |
| 创建 | `volcenginecc_clb_server_group` | `volcenginecc_clb_server_group.this` |
| 创建 | `volcenginecc_clb_listener` | `volcenginecc_clb_listener.this` |
| 创建 | `volcenginecc_natgateway_ngw` | `volcenginecc_natgateway_ngw.this` |
| 创建 | `volcenginecc_vpc_eip` | `volcenginecc_vpc_eip.nat` |
| 创建 | `volcenginecc_natgateway_snatentry` | `volcenginecc_natgateway_snatentry.this` |
| 创建 | `volcenginecc_vpc_route_table` | `volcenginecc_vpc_route_table.private` |
| 创建 | `volcenginecc_rdsmysql_allow_list` | `volcenginecc_rdsmysql_allow_list.this` |
| 创建 | `volcenginecc_rdsmysql_instance` | `volcenginecc_rdsmysql_instance.this` |
| 创建 | `volcenginecc_redis_allow_list` | `volcenginecc_redis_allow_list.this` |
| 创建 | `volcenginecc_redis_instance` | `volcenginecc_redis_instance.this` |
| 创建 | `volcenginecc_tos_bucket` | `volcenginecc_tos_bucket.this` |
| 创建 | `volcenginecc_tls_project` | `volcenginecc_tls_project.this` |
| 创建 | `volcenginecc_tls_topic` | `volcenginecc_tls_topic.this` |
| 创建 | `volcenginecc_cloudmonitor_rule` | `volcenginecc_cloudmonitor_rule.this` |

表格列出 26 个资源声明，不代表固定实例数量；根模块没有 Data Source 或本地子模块。复用时不创建 VPC/子网或对应数据实例与白名单；ALB/CLB 二选一。开启 ASG 后静态 Web ECS 被启动模板和伸缩组替代，App 仍为静态 ECS；开启日志创建一个 TLS 项目和 application/access/health 三个 Topic，每个监控 key 创建一条规则。

## 7. 输入（Inputs）

| 名称 | 类型 | 默认值 | 创建模式下是否必填 | 说明 |
|---|---|---|---|---|
| `name` | `string` | 无 | 是 | 名称前缀及 Project 标签；3–31 位小写字母、数字或连字符，以字母开头。 |
| `environment` | `string` | `"dev"` | 否 | `dev` 或 `prod`；生产约束见下文。 |
| `tags` | `map(string)` | `{}` | 否 | 归属标签；Project/Environment 由模块覆盖。 |
| `vpc_cidr` | `string` | `"10.20.0.0/16"` | 否 | 合法 IPv4 VPC CIDR；复用时与实际网络一致。 |
| `zones` | `map(object)` | 无 | 是 | 可用区和四层 CIDR，完整字段及匹配规则见下文。 |
| `existing_vpc_id` | `string` | `null` | 否 | 非空时复用 VPC，并提供全部已有子网。 |
| `existing_subnet_ids` | `map(string)` | `{}` | 否 | 复用 VPC 时必填；key 为可用区逻辑 key 加层级后缀。 |
| `web` | `object` | 无 | 是 | Web 镜像、规格、每区实例数及系统盘。 |
| `app` | `object` | 无 | 是 | App 镜像、规格、每区实例数及系统盘。 |
| `key_pair_name` | `string` | 无 | 是 | 已有 ECS 密钥对名称。 |
| `web_port` | `number` | `8080` | 否 | 负载均衡 → Web 端口；1–65535 的整数。 |
| `app_port` | `number` | `8080` | 否 | Web → App 端口；1–65535 的整数。 |
| `load_balancer` | `object` | 无 | 是 | 入口类型、来源、HTTPS 与健康检查配置。 |
| `autoscaling` | `object` | `{}` | 否 | 可选 Web ASG 容量；不创建指标伸缩策略。 |
| `existing_database_id` | `string` | `null` | 否 | 复用私网 MySQL，与 `database` 二选一。 |
| `database` | `object` | `null` | 是，新建 MySQL 时 | MySQL 规格、存储、账户及备份。 |
| `database_password` | `string` | `null` | 是，新建 MySQL 时 | 敏感密码，创建时不能为 null；遵守服务端密码规则。 |
| `existing_cache_id` | `string` | `null` | 否 | 复用私网 Redis，与 `cache` 二选一。 |
| `cache` | `object` | `null` | 是，新建 Redis 时 | Redis 版本、容量及备份时间。 |
| `cache_password` | `string` | `null` | 是，新建 Redis 时 | 敏感密码，创建时不能为 null；不启用免密访问。 |
| `bucket_name` | `string` | 无 | 是 | 地域唯一，3–63 位小写字母、数字或连字符，两端为字母或数字。 |
| `enable_logs` | `bool` | `true` | 否 | 创建 TLS 项目和三个 Topic；生产必须开启。 |
| `log_retention_days` | `number` | `30` | 否 | TLS 保留 1–3650 天，整数。 |
| `deletion_protection` | `bool` | `false` | 否 | ECS、新建 RDS/Redis、ALB 删除保护；正常生产必须开启。 |
| `allow_protection_disable` | `bool` | `false` | 否 | 生产维护窗口允许关闭保护；自身不执行销毁。 |
| `monitoring` | `map(object)` | `{}` | 否 | 显式指标规则与联系人组，按 Project 标签筛选资源。 |
| `service_egress` | `map(object)` | `{}` | 否 | Web/App 共同使用的显式端点出站规则；实际运行按需要提供。 |
| `nat` | `object` | `{}` | 否 | 可选 VPC 级共享出站 NAT、EIP 及 Web/App SNAT。 |

对象类型的完整字段如下；`optional` 内的值为子字段默认值，未指定默认值的可选字段为 `null`。根模块的 `{}` 对象默认会应用子字段默认值。

```hcl
zones = map(object({
  zone_id = string, edge_cidr = string, web_cidr = string
  app_cidr = string, data_cidr = string
}))

web = object({
  image_id = string, instance_type = string
  count_per_zone = optional(number, 1), disk_size = optional(number, 40)
  disk_type = optional(string, "ESSD_PL0")
})
app = object({
  image_id = string, instance_type = string
  count_per_zone = optional(number, 1), disk_size = optional(number, 40)
  disk_type = optional(string, "ESSD_PL0")
})

load_balancer = object({
  kind = optional(string, "alb"), public = optional(bool, false)
  https = optional(bool, false), certificate_id = optional(string)
  domain = optional(string), allowed_cidrs = set(string)
  health_check_cidrs = optional(set(string), [])
  health_path = optional(string, "/health"), bandwidth = optional(number, 10)
  clb_spec = optional(string, "small_1")
})
autoscaling = object({
  enabled = optional(bool, false), min = optional(number, 2)
  desired = optional(number, 2), max = optional(number, 6)
})
database = object({
  node_spec = string, engine_version = optional(string, "MySQL_8_0")
  storage_space = optional(number, 100), storage_type = optional(string, "CloudESSD_PL0")
  account_name = optional(string, "webadmin"), backup_retention_days = optional(number, 7)
})
cache = object({
  engine_version = optional(string, "6.0"), shard_capacity = optional(number, 1024)
  backup_hour = optional(number, 3)
})
monitoring = map(object({
  region = string, namespace = string, sub_namespace = string
  metric_name = string, metric_unit = string, threshold = string
  contact_group_ids = set(string), statistics = optional(string, "avg")
  comparison_operator = optional(string, ">"), evaluation_count = optional(number, 3)
}))
service_egress = map(object({
  cidr = string, protocol = string, port = number
}))
nat = object({
  enabled = optional(bool, false), bandwidth = optional(number, 10)
  zone_key = optional(string)
})
```

`zones` 至少一个可用区，`zone_id` 不重复；全部子网为合法 IPv4 网段、位于 VPC 内且互不重叠。复用 VPC 时，`existing_subnet_ids` 的 key 必须精确匹配每个可用区逻辑 key 与 `-edge`、`-web`、`-app`、`-data` 后缀的组合；新建时该映射为空。MySQL/Redis 节点按逻辑 key 排序选择前一或前两个可用区，因此应保持 key 稳定。

`web/app.count_per_zone` 为 1–1024 的整数，系统盘至少 40 GiB；规格与盘类型由目标地域决定。`load_balancer.kind` 为 `alb/clb`，`allowed_cidrs` 非空且均为合法 IPv4 CIDR；HTTPS 同时提供证书中心 ID 和域名，健康路径以 `/` 开头，带宽至少 1 Mbps。CLB 要求非空 `health_check_cidrs`，但当前 Web 安全组来源固定为 `100.64.0.0/10`，该参数不会改变安全组规则。

ASG 容量为整数，满足 `1 <= min <= desired <= max`；生产 `min` 不小于可用区数。新建 MySQL 存储至少 20 GiB，备份保留 7–3650 天；Redis 容量至少 256 MiB，备份小时为 0–23 的整数，单节点开发 Redis 不配置备份。生产创建跨区双节点 MySQL 和跨区双节点 Redis，要求至少两区、HTTPS、日志及保护；仅显式维护开关允许关闭保护。

每条监控规则提供官方指标的地域、namespace/sub_namespace、名称、单位、阈值及非空联系人组，`evaluation_count >= 1`。服务出站为合法 IPv4 CIDR、`tcp/udp` 与整数端口 1–65535；模块不创建这些端点或其权限。NAT 带宽为 1–200 Mbps，开启时 `zone_key` 必须匹配 `zones`，每个 VPC 只创建一个网关；复用 VPC 的路由由调用方管理。两套 example 的数据库/缓存密码均为必填且非空，即使 complete 复用数据实例也要提供。

## 8. 输出（Outputs）

| 名称 | 类型 | 说明 |
|---|---|---|
| `network` | `object` | `vpc_id`、`subnet_ids`、`security_group_ids`，供私网接入和资源引用；可能包含已有资源 ID。 |
| `compute` | `object` | `instances` 按稳定 key 输出静态 ECS 的 `id`、`network_interface`；`scaling_group_id` 仅启用 ASG 时非空，成员由服务管理。 |
| `entrypoint` | `object` | 入口 `id`、`server_group_id`、`domain`、`alb_dns_name`、`clb_public_ip`；仅对应类型的地址非空，域名可空。 |
| `data` | `object` | `database_id`、`cache_id`、`mysql_endpoints`、`redis_private_address`；复用时端点为 null，由调用方查询。 |
| `storage_and_logs` | `object` | `bucket_name`、`tls_project_id`、`topic_ids`、`monitoring_rule_ids`；关闭日志时项目 ID 为 null、Topic 映射为空，无监控时规则映射为空。 |
| `nat` | `object` | `gateway_ids`、`eip_ids`、`snat_ids`、`route_table_ids`；关闭 NAT 时均为空映射，各可用区指向同一网关/EIP。 |

ID、地址和域名为字符串，资源集合为映射；`network_interface`、`mysql_endpoints` 保留 Provider 返回的嵌套结构。调用方使用入口配置 DNS，使用私网计算/数据端点配置应用，使用存储与日志 ID 配置访问及采集。两套 example 只输出前五组的 `architecture`，不转发 `nat`。

## 9. 其他说明（Notes）

模块通过 ID 复用已有资源，不执行 import，不调整已有数据实例的账户、白名单、备份、保护或网络路由；这些资源也不会被模块销毁。名称、可用区 key、镜像、子网或资源规格变化可能导致更新或替换，执行前以 Plan 为准。

入口 ACL 放行客户端来源；Web 安全组仅允许 `100.64.0.0/10` 到 `web_port`，Web → App 使用 `app_port`，App → 数据层使用 3306/6379 与应用子网白名单。业务及显式端点允许规则优先级为 1，兜底拒绝为 99，平台追加的默认允许规则为 100，因此不会绕过拒绝。没有默认 SSH 入站或默认全放通出站；NAT 不替代安全组授权。

开启 NAT 后，仅 Web/App 配置 SNAT 和独立路由表。data 子网仍使用系统路由表，NAT 服务可能向该表自动加入 `0.0.0.0/0 → NAT`；当前代码没有将 data 绑定到独立隔离路由表，不能声称其不存在公网默认路由。data 无 SNAT，已验证链路未发现数据层公网暴露，但尚未直接实测 data 主动出网。

ALB 可接入 TLS 访问日志；创建 Topic 不等于应用已采集日志。CLB 的访问日志与删除保护不由本模块配置。HTTP CLB 健康检查省略覆盖端口，随 Web 后端 `8080`；Web 业务端口仍保留。ASG 启动模板在 Provider `0.0.73` 存在字段回读异常，两套示例关闭 ASG，该路径尚未验收通过。

销毁受保护资源前，将 `deletion_protection=false`；生产还要显式设置 `allow_protection_disable=true`，审阅更新计划并核对 ECS/RDS/Redis/ALB 的实际保护状态。ALB 关闭保护更新可能出现替换计划，应先通过原生服务关闭对应 ALB 的 `DeleteProtection`，核对计划后再继续。清空 TOS 全部版本；RDS 最终备份可能保留，Redis 最终备份由服务保留七天。密码虽标记 sensitive，仍会写入 State，由调用方保管 State 和凭据。

相同实现的隔离副本曾完成 basic/complete 空 State 一次 Apply 和应用初始化后的业务链路验证；当前 Registry 安装未验证。两套二次 `terraform plan` 各出现四项 RDS/TOS/安全组漂移，尚未达到 `No changes`；标准 Destroy 曾因 TOS/CLB 异步任务及 Redis 白名单解绑失败，后续重试清理不代表完整生命周期通过。生产平台测试还出现删除保护关闭、TOS 版本状态为空，生产使用前应核对原生服务状态。本次只修正文档，没有重新执行云验收。
