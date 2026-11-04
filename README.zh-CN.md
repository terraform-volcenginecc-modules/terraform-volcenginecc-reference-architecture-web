# terraform-volcenginecc-reference-architecture-web

可组合的火山引擎 Web 基础设施 Module，包含分层网络、负载均衡、Web/应用计算、私网 MySQL/Redis、对象存储、日志与监控。

## 1. 概述（Overview）

支持单可用区开发环境和多可用区生产环境，创建 VPC/子网、安全组、ECS 或 Web ASG、ALB/CLB、RDS MySQL、Redis、TOS、TLS 及可选 CloudMonitor 规则。已有网络和数据资源仍归调用方所有；提供 ID 不代表 import 纳管。

每区划分 edge、web、app、data 四层子网。仅负载均衡提供公网入站入口；ECS 不绑定公网 EIP，NAT 可选为 Web/应用子网提供出站。数据子网没有 Module 管理的公网默认路由。应用安装、代理/数据库配置、DNS、证书、服务身份和日志 Agent 由调用方负责。需求中的 CLS 能力使用火山引擎 TLS 实现。

**最终云复测部分通过，完整验收仍未完成。** 安全组维护后完整规则校验 4/4 通过；complete 两台应用 ECS 创建成功，Redis 业务操作通过。启动模板回读、NAT 并发、RDS/TOS 漂移及未通过的业务链路仍需处理；销毁重试已清理实例与网络，3 个 Redis 最终备份待到期回查。

## 2. 用法（Usage）

在调用方 root 中配置 Provider、地域、凭据与 backend。提供已核实的可用区 ID、预装 Web/应用的镜像、实例规格、已有 ECS 密钥对、RDS 规格、地域唯一 Bucket 名称及显式入口 CIDR。开通所需服务并确认配额和权限。Web 镜像必须提供配置的健康检查路径。

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
  source = "terraform-volcenginecc-modules/reference-architecture-web/volcenginecc"

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

output "architecture" {
  value = {
    network = module.web.network, compute = module.web.compute
    entrypoint = module.web.entrypoint, data = module.web.data
    storage_and_logs = module.web.storage_and_logs, nat = module.web.nat
  }
}
```

此最小调用使用私网 HTTP ALB。通过 `service_egress` 提供实际私网 DNS/TOS/TLS 端点 CIDR；必须具备路由、服务权限和应用配置。凭据使用 `VOLCENGINE_ACCESS_KEY`、`VOLCENGINE_SECRET_KEY`，不解码。密码通过 `TF_VAR_database_password`、`TF_VAR_cache_password` 提供。真实凭据和部署参数不要进入 Git。

Registry source 使用当前 Web 模块名，遵循 `terraform-volcenginecc-modules/vpc/volcenginecc` 的命名模式。本模块尚未发布，不填写虚构版本，Registry 安装未验证。本地验收仅在隔离副本中将 source 指向待测模块。

发布后，在独立调用目录中选择一个引擎并准备已核实的 `deployment.tfvars`。Apply 前审阅成本与权限。

```bash
terraform init
terraform plan -var-file=deployment.tfvars -out=deployment.tfplan
terraform apply deployment.tfplan
terraform plan -var-file=deployment.tfvars
terraform output -json
```

```bash
tofu init
tofu plan -var-file=deployment.tfvars -out=deployment.tfplan
tofu apply deployment.tfplan
tofu plan -var-file=deployment.tfvars
tofu output -json
```

引擎验证使用独立 State、锁文件和缓存。应用通过输出中的私网计算/数据端点及存储/日志 ID 完成配置。验证入口、层间连接、日志与告警，再确认二次 Plan No changes。

## 3. 示例（Examples）

| 示例目录 | 场景 | 网络与计算 | 入口、数据与运维 |
|---|---|---|---|
| examples/basic | 单区开发、最小三层 Web | 四个子网、一台 Web ECS 和一台应用 ECS、一个出站 NAT | 公网 HTTP CLB 与 ACL；私网单节点 MySQL/Redis；私有 TOS、TLS、MySQL 备份；Standalone Redis 不支持备份 |
| examples/complete | 多区生产基线 | 八个子网、均衡 Web ASG、每区一台应用 ECS；新建 VPC 时每区一个出站 NAT | 公网 HTTPS ALB、证书/域名、跨区 MySQL/Redis、ALB 日志、90 天 TLS、显式监控、30 天 MySQL 备份、Redis 备份、TOS 版本控制、保护及所有者/成本标签 |

complete 支持已有网络/数据库/缓存 ID，以及可选 CLB 入口。复用网络须匹配示例固定子网 CIDR。已有网络路由/NAT、数据鉴权、白名单、备份和保护由调用方管理。CLB 日志/保护限制见其他说明。ASG 不创建指标伸缩策略。

## 4. 版本要求（Requirements）

| 要求 | 值 |
|---|---|
| 共同引擎约束 | >= 1.5.7, < 1.12.0 |
| 精确验证引擎 | Terraform 1.5.7 与 OpenTofu 1.11.8；区间内其他版本未验证 |
| 最低 Provider | volcengine/volcenginecc >= 0.0.73 |
| 验证/示例 Provider | Registry 发布版 0.0.73 |
| 网络 | 可用区不重复，IPv4 子网不重叠且位于 VPC CIDR 内 |
| 生产 | 至少两区、HTTPS、日志、删除保护；显式维护开关允许关闭保护；ASG min 不小于区数 |
| 外部前置 | 已开通服务、配额、镜像、实例规格、密钥对、端点路由/权限；使用 HTTPS/监控时须提供证书/域名及官方指标/联系人组 |

## 5. Providers（Providers）

| 名称 | 来源 | 约束 | 文档 |
|---|---|---|---|
| volcenginecc | volcengine/volcenginecc | 根模块 >= 0.0.73；示例和验证 = 0.0.73 | [Registry](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs) |

可复用根模块不包含 Provider 配置。保留调用方锁文件；静态验证使用独立锁/缓存及 Registry 直接安装，禁用 development overrides。不使用其他云 Provider、Data Source、provisioner 或脚本资源。

## 6. 资源（Resources）

以下均为 managed resource。数量按新建网络/数据及 complete 一条监控规则计算：basic 27 个，complete 39 个。数量不包含云端 ASG 成员及服务隐式资源。

| Resource 类型 | 地址名称 | basic / complete | 职责与官方文档 |
|---|---|---|---|
| `volcenginecc_vpc_vpc` | this | 1 / 1 | [VPC](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/vpc_vpc)，可复用 |
| `volcenginecc_vpc_subnet` | this | 4 / 8 | [分层子网](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/vpc_subnet)，可成套复用 |
| `volcenginecc_vpc_security_group` | this | 2 / 2 | [Web/应用流量矩阵](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/vpc_security_group) |
| `volcenginecc_ecs_instance` | this | 2 / 2 | [私网计算](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/ecs_instance)，complete 静态实例均为应用节点 |
| `volcenginecc_ecs_launch_template` | web | 0 / 1 | [ASG 模板](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/ecs_launch_template) |
| `volcenginecc_autoscaling_scaling_group` | web | 0 / 1 | [Web 容量和注册](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/autoscaling_scaling_group) |
| `volcenginecc_alb_load_balancer` | this | 0 / 1 | [ALB](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/alb_load_balancer) |
| `volcenginecc_alb_acl` | this | 0 / 1 | [ALB 入站 ACL](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/alb_acl) |
| `volcenginecc_alb_listener` | this | 0 / 1 | [HTTP/HTTPS 监听](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/alb_listener) |
| `volcenginecc_alb_server_group` | this | 0 / 1 | [Web 后端组](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/alb_server_group) |
| `volcenginecc_clb_clb` | this | 1 / 0 | [可选 CLB](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/clb_clb) |
| `volcenginecc_clb_acl` | this | 1 / 0 | [CLB 入站 ACL](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/clb_acl) |
| `volcenginecc_clb_listener` | this | 1 / 0 | [CLB 监听](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/clb_listener) |
| `volcenginecc_clb_server_group` | this | 1 / 0 | [CLB Web 后端](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/clb_server_group) |
| `volcenginecc_natgateway_ngw` | this | 1 / 2 | [出站 NAT](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/natgateway_ngw) |
| `volcenginecc_vpc_eip` | nat | 1 / 2 | [NAT 出站 EIP](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/vpc_eip) |
| `volcenginecc_natgateway_snatentry` | this | 2 / 4 | [Web/应用 SNAT](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/natgateway_snatentry) |
| `volcenginecc_vpc_route_table` | private | 1 / 2 | [Web/应用默认路由](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/vpc_route_table)，不关联数据子网，不创建 DNAT |
| `volcenginecc_rdsmysql_instance` | this | 1 / 1 | [私网 MySQL](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/rdsmysql_instance)，可复用 |
| `volcenginecc_rdsmysql_allow_list` | this | 1 / 1 | [应用 CIDR 白名单](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/rdsmysql_allow_list) |
| `volcenginecc_redis_instance` | this | 1 / 1 | [鉴权私网 Redis](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/redis_instance)，可复用 |
| `volcenginecc_redis_allow_list` | this | 1 / 1 | [应用 CIDR 白名单](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/redis_allow_list) |
| `volcenginecc_tos_bucket` | this | 1 / 1 | [私有 Bucket](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/tos_bucket)，生产版本控制 |
| `volcenginecc_tls_project` | this | 1 / 1 | [日志项目](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/tls_project) |
| `volcenginecc_tls_topic` | this | 3 / 3 | [应用/访问/健康 Topic](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/tls_topic) |
| `volcenginecc_cloudmonitor_rule` | this | 0 / 1 | [显式指标告警](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/cloudmonitor_rule)，每输入 key 一条 |

| 来源 | 目标 | 端口 | 控制 |
|---|---|---|---|
| 显式客户端 CIDR | 负载均衡 | 80/443 | Listener ACL |
| 官方 ALB/CLB 转发网段 100.64.0.0/10 | Web | TCP web_port，默认 8080 | Web 安全组入站；CLB 不绕过安全组 |
| Web 子网 | 应用 | TCP app_port，默认 8080 | Web 出站与应用入站 |
| 应用子网 | 数据子网 | TCP 3306/6379 | 应用出站与数据库/缓存白名单 |
| Web/应用 | 显式服务端点 | 指定 TCP/UDP 端口 | service_egress 与调用方服务路由 |

未配置 SSH 入站。Provider 0.0.73 首次创建可附加默认全放通出站；complete 第二阶段维护已删除该规则，完整规则 4/4 校验通过。按其他说明执行维护并独立回查。

## 7. 输入（Inputs）

以下完整列出 `object`、`map(object)` 字段。必填字段没有默认值，可选字段默认值由 Module 应用。顶层 `null` 分别表示没有创建配置或没有已有 ID。

| 名称 | 类型 | 默认值 | 必填条件 / 说明 |
|---|---|---|---|
| `name` | string | 无 | 必填；3–31 位小写字母/数字/连字符，字母开头；Project 标签 |
| `environment` | string | "dev" | dev/prod；生产强制拓扑/HTTPS/日志/保护 |
| `tags` | map(string) | {} | Project/Environment 由 Module 值覆盖 |
| `vpc_cidr` | string | "10.20.0.0/16" | IPv4；复用时也必须准确描述已有 VPC |
| `zones` | map(object) | 无 | 必填；稳定 key、不同 zone ID、四层 CIDR 不重叠且在 VPC 内 |
| `existing_vpc_id` | string | null | 复用须提供全部 existing_subnet_ids；必须关闭 NAT |
| `existing_subnet_ids` | map(string) | {} | 精确 key：zone key 加 -edge/-web/-app/-data |
| `web` | object | 无 | 必填；预装镜像与实例规格 |
| `app` | object | 无 | 必填；预装镜像与实例规格 |
| `key_pair_name` | string | 无 | 必填；已有密钥对，私网维护通道 |
| `web_port` | number | 8080 | 整数 1–65535 |
| `app_port` | number | 8080 | 整数 1–65535 |
| `load_balancer` | object | 无 | 必填；allowed_cidrs 非空，默认私网 ALB |
| `autoscaling` | object | {} | 可选 Web ASG，替代静态 Web ECS |
| `existing_database_id` | string | null | 与 database 二选一；已有服务设置由调用方管理 |
| `database` | object | null | 新建 MySQL 必填，与 existing_database_id 互斥 |
| `database_password` | string, sensitive | null | 新建 MySQL 必填；敏感值仍保存在 State |
| `existing_cache_id` | string | null | 与 cache 二选一；已有服务设置由调用方管理 |
| `cache` | object | null | 新建 Redis 必填；{} 使用字段默认值 |
| `cache_password` | string, sensitive | null | 新建 Redis 必填；不允许免密访问 |
| `bucket_name` | string | 无 | 必填；3–63 位小写字母/数字/连字符，首尾为字母数字，地域唯一 |
| `enable_logs` | bool | true | 生产必须 true |
| `log_retention_days` | number | 30 | 整数 1–3650 |
| `deletion_protection` | bool | false | 生产必须 true，维护开关显式允许关闭时除外 |
| `allow_protection_disable` | bool | false | 显式维护开关，不自动销毁资源 |
| `monitoring` | map(object) | {} | 官方指标/联系人组；complete 至少一条 |
| `service_egress` | map(object) | {} | 实际 IPv4 端点 CIDR、显式 TCP/UDP 端口 |
| `nat` | object | {} | 每区出站 NAT，仅支持新建网络 |

| 字段 | 类型 | 默认值 | 条件 / 含义 |
|---|---|---|---|
| `zones.*.zone_id` | string | 无 | 必填 |
| `zones.*.edge_cidr` | string | 无 | 必填 IPv4 CIDR |
| `zones.*.web_cidr` | string | 无 | 必填 IPv4 CIDR |
| `zones.*.app_cidr` | string | 无 | 必填 IPv4 CIDR |
| `zones.*.data_cidr` | string | 无 | 必填 IPv4 CIDR |
| `web.image_id` | string | 无 | 必填预装 Web 镜像 |
| `web.instance_type` | string | 无 | 必填可用规格 |
| `web.count_per_zone` | number | 1 | 可选正整数；Web ASG 容量不使用此字段 |
| `web.disk_size` | number | 40 | 可选，至少 40 GiB |
| `web.disk_type` | string | "ESSD_PL0" | 可选 |
| `app.image_id` | string | 无 | 必填预装应用镜像 |
| `app.instance_type` | string | 无 | 必填可用规格 |
| `app.count_per_zone` | number | 1 | 可选正整数 |
| `app.disk_size` | number | 40 | 可选，至少 40 GiB |
| `app.disk_type` | string | "ESSD_PL0" | 可选 |
| `load_balancer.kind` | string | "alb" | 可选 alb/clb |
| `load_balancer.public` | bool | false | 可选公网入站入口 |
| `load_balancer.https` | bool | false | 可选；生产必须 true |
| `load_balancer.certificate_id` | string | null | HTTPS 必填，证书中心 ID |
| `load_balancer.domain` | string | null | HTTPS 必填，DNS 由调用方配置 |
| `load_balancer.allowed_cidrs` | set(string) | 无 | 必填非空 IPv4 集合 |
| `load_balancer.health_check_cidrs` | set(string) | [] | CLB 必填非空官方来源 |
| `load_balancer.health_path` | string | "/health" | 可选，以 / 开头 |
| `load_balancer.bandwidth` | number | 10 | 可选，至少 1 Mbps |
| `load_balancer.clb_spec` | string | "small_1" | 可选 CLB 规格 |
| `autoscaling.enabled` | bool | false | 可选 |
| `autoscaling.min` | number | 2 | 可选整数 >= 1；生产 >= 区数 |
| `autoscaling.desired` | number | 2 | 可选整数；min <= desired <= max |
| `autoscaling.max` | number | 6 | 可选整数 |
| `database.node_spec` | string | 无 | 提供 database 时必填 |
| `database.engine_version` | string | "MySQL_8_0" | 可选 |
| `database.storage_space` | number | 100 | 可选，至少 20 GiB |
| `database.storage_type` | string | "CloudESSD_PL0" | 可选 |
| `database.account_name` | string | "webadmin" | 可选超级账户 |
| `database.backup_retention_days` | number | 7 | 可选，7–3650 天 |
| `cache.engine_version` | string | "6.0" | 可选 |
| `cache.shard_capacity` | number | 1024 | 可选，至少 256 MiB |
| `cache.backup_hour` | number | 3 | 可选整数 0–23，UTC+8；Standalone 无备份 |
| `monitoring.*.region` | string | 无 | 必填 |
| `monitoring.*.namespace` | string | 无 | 必填官方指标 namespace |
| `monitoring.*.sub_namespace` | string | 无 | 必填官方 sub-namespace |
| `monitoring.*.metric_name` | string | 无 | 必填官方指标 |
| `monitoring.*.metric_unit` | string | 无 | 必填官方单位 |
| `monitoring.*.threshold` | string | 无 | 必填 |
| `monitoring.*.contact_group_ids` | set(string) | 无 | 必填非空已有联系人组 |
| `monitoring.*.statistics` | string | "avg" | 可选 |
| `monitoring.*.comparison_operator` | string | ">" | 可选 |
| `monitoring.*.evaluation_count` | number | 3 | 可选，>= 1 |
| `service_egress.*.cidr` | string | 无 | 必填 IPv4 CIDR |
| `service_egress.*.protocol` | string | 无 | 必填 tcp/udp |
| `service_egress.*.port` | number | 无 | 必填整数 1–65535 |
| `nat.enabled` | bool | false | 可选，复用 VPC 时不得开启 |
| `nat.bandwidth` | number | 10 | 可选，1–200 Mbps |

## 8. 输出（Outputs）

`compute.instances.*.network_interface` 为 object：network_interface_id、mac_address、primary_ip_address、subnet_id、vpc_id 为 string，ipv_6_address_count 为 number，ipv_6_addresses、private_ip_addresses、security_group_ids 为 set(string)。`data.mysql_endpoints` 为 set(object)，其中 endpoint_id、endpoint_name、connection_mode、read_write_mode 为 string，addresses 为 set(object)。每个 address 的 domain、ip_address、port、network_type、subnet_id、eip_id、internet_protocol 为 string，dns_visibility、eip_locked 为 bool；其他端点设置遵循已链接的 RDS Schema。Redis 私网地址为域名 string。ALB 时 CLB IP=null；私网 CLB 的地址缺省和值遵循 Provider 回读。

全部输出为非敏感 object；资源 ID 默认归 Module 所有，显式复用资源除外。端点/接口集合遵循 Provider 0.0.73 Schema，创建时回读字段。密码不输出。

| 名称 | 类型 / 字段 | 含义与空值条件 |
|---|---|---|
| `network` | object: vpc_id string, subnet_ids map(string), security_group_ids map(string) | 稳定逻辑 key；复用 VPC/子网仍归调用方所有 |
| `nat` | object of map(string): gateway_ids, eip_ids, snat_ids, route_table_ids | 关闭时各字段为 {}；此输出声明在 outputs.tf |
| `compute` | object: instances map(object({id=string, network_interface=provider object})), scaling_group_id string or null | 关闭 ASG 时 ID 为 null；ASG 成员由云端管理，静态应用实例仍存在 |
| `entrypoint` | object: id/server_group_id string, domain/alb_dns_name/clb_public_ip string or null | 未提供域名时 domain=null；CLB 时 ALB DNS=null；ALB 时 CLB IP=null，私网 CLB 遵循 Provider 回读；DNS 记录由调用方管理 |
| `data` | object: database_id/cache_id string, mysql_endpoints set(object) or null, redis_private_address string or null | 新建实例私网端点；复用对应服务时端点字段为 null，地址由调用方查询 |
| `storage_and_logs` | object: bucket_name string, tls_project_id string or null, topic_ids/monitoring_rule_ids map(string) | 关闭日志时项目为 null、topics={}；无监控规则时 IDs={} |

示例输出 `architecture`，包含 network、compute、entrypoint、data、storage_and_logs，不转发根 nat 输出。条件空值由输入决定；必需 ID 不会因属性错误被静默替换为 null。

## 9. 其他说明（Notes）

- 所有权和 import：提供已有 ID 不导入或修改已有网络/数据设置。确认地域、CIDR、路由、白名单、鉴权、备份与保护。域名、证书、镜像、密钥对、联系人组仍归调用方所有。数据端点应位于数据子网范围内，否则需显式补充出站规则。
- 替换：zone key、层级 key、实例索引决定地址。重命名 key、切换新建/复用或 ECS/ASG 可能删除/重建资源。VPC/子网/可用区/镜像/规格变更应审阅实际替换 Plan；真实云更新和替换尚未验证。
- ASG：ASG 管理注册时后端 `servers=null`，不得同时管理静态成员。Optional+Computed 回读须真实验证 No changes。ASG 成员不继承独立 ECS 资源的删除保护。
- CLB：Provider 0.0.73 的日志 enabled/tls_enabled 为 computed-only。绑定日志目标不能证明日志已开启，须回查并记录控制台操作。CLB 没有与 ALB 等价的删除保护。健康检查 CIDR 使用目标地域官方来源。
- 数据和备份：不创建 MySQL/Redis 公网地址资源。MySQL 每日备份使用 UTC 18:00Z–19:00Z，生产 Redis 备份小时为 UTC+8。Standalone Redis 不支持备份。TOS 版本控制不提供跨地域复制、KMS 或对象锁。
- State 和标签：敏感值仍存在 State/Plan。使用已核实的加密、锁定、权限隔离 backend。支持标签的资源使用统一标签，白名单 Schema 无 tags 字段。凭据、真实 tfvars、State、Plan 不进入 Git。
- 销毁维护：保留必要数据并清空 Bucket 所有版本，保持 prod 拓扑，将 deletion_protection=false、allow_protection_disable=true 用于维护和后续 Destroy。先审阅维护 Plan；Provider 0.0.73 对 ALB 关闭保护会计划替换，不要直接应用包含受保护 ALB 替换的整体 Plan。本轮只对已存在 ECS/MySQL/Redis 定向维护及其安全组依赖执行 0 新增、6 原地更新、0 销毁的 Plan，Apply 成功；这是清理维护，不能作为整体部署通过的依据。通过 ALB 控制台关闭本次实例删除保护，或对精确 LoadBalancerId 调用官方 ModifyLoadBalancerAttributes 将 DeletionProtection 设为 off，再独立回查 ALB/MySQL/Redis 保护均已关闭。 随后执行普通 Destroy。若 Redis 白名单报 AllowListBindInstanceCannotDelete，先查询确认实例已删除及白名单当前绑定；若 TOS 已确认 NotFound 但异步删除任务持续挂起，停止当前 Terraform 命令并保存结果。前一命令结束后，重新执行相同 Destroy，让 Provider 刷新实际状态；禁止并行启动第二个 Destroy。本轮重试 exit 0，State 为空，41 个已知显式/隐式对象均确认不存在。不要使用 state rm 代替删除确认。MySQL 最终备份如无需保留，对精确实例调用 ModifyBackupPolicy，设置 DataKeepPolicyAfterReleased=None 后查询备份数为零；Redis 最终备份强制保留七天，须到期回查，当前已知仍有 3 个。
- 工程：仓库参照 VPC 模块结构，包含可复用根模块、basic/complete 示例、双语 README、outputs.tf、LICENSE、SECURITY.md、CHANGELOG.md 和 Terraform 格式检查钩子。领域 .tf 文件共享根模块生命周期。使用版本要求中的引擎运行 `terraform fmt -check -recursive` 或 `tofu fmt -check -recursive`。本地验收报告、测试 fixture、凭据和缓存不纳入版本管理。静态检查不证明真实 update/remove/replace 行为。

安全组两阶段维护：沿用 security-group/examples 的“创建后回读，再维护并检查最终 Plan”流程。本模块已显式填写规则十字段，首次创建后平台仍可能附加默认全放通出站。先通过输出的安全组 ID 查询实际规则，再对已创建的 Web/App 安全组执行维护 Plan；确认仅原地删除配置外默认规则、保留业务和 service_egress 规则，且没有新增或替换后，才 Apply。本模块没有 system_default_egress_rules 输入，无需把全放通规则加入期望配置。complete 最终复测在第二阶段维护后，入站/出站十字段校验 4/4 通过。

以下命令适用于调用名 module.web，仅用于首次创建后的定向维护；若地址不同，按实际 State 地址调整。若 Plan 包含创建/替换或安全组仍 tainted，先排查，不能直接应用。维护完成后必须运行无 target 的普通 Plan，并通过云端查询比较完整规则集合；exit 0 才代表整体 No changes。其他资源漂移不能因安全组通过而判定消失。OpenTofu 命令是等价操作说明，真实云维护仅验证了 Terraform 1.5.7。

```bash
terraform plan -var-file=deployment.tfvars \
  -target='module.web.volcenginecc_vpc_security_group.this["web"]' \
  -target='module.web.volcenginecc_vpc_security_group.this["app"]' \
  -out=sg-maintenance.tfplan
terraform apply sg-maintenance.tfplan
terraform plan -var-file=deployment.tfvars -detailed-exitcode
```

```bash
tofu plan -var-file=deployment.tfvars \
  -target='module.web.volcenginecc_vpc_security_group.this["web"]' \
  -target='module.web.volcenginecc_vpc_security_group.this["app"]' \
  -out=sg-maintenance.tfplan
tofu apply sg-maintenance.tfplan
tofu plan -var-file=deployment.tfvars -detailed-exitcode
```

其余限制：创建前用官方 DescribeImages 按 InstanceType 过滤兼容镜像，不能仅按 OS 名选择；最终 complete 使用兼容 Debian10 镜像，两台应用 ECS 创建成功，basic 的镜像不匹配未单独重测。同 VPC 多 NAT 若 ResourceConflict，确认已有网关和在途操作，再重新 Plan；可在审阅后用 -parallelism=1 串行重试，但本轮未验证该方式能使完整部署成功。启动模板 volumes/network_interfaces 回读 null 尚无已验证规避，Web ASG 与 HTTPS 入口仍未通过。RDS public_download_enable=false 实际仍为 true，TOS acl_grant 回读 null（独立 ACL 仅 Owner FULL_CONTROL）；不能用 ignore_changes 将这些差异判为已修复。维护后没有整体 No changes 的证据。
