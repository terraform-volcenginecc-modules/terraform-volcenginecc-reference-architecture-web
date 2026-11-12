# COMPLETE Web 架构 示例

模块 source 为 `terraform-volcenginecc-modules/reference-architecture-web/volcenginecc`，模块版本约束为 `version = "~> 1.0"`（>= 1.0.0、< 2.0.0），与 Provider 版本要求分别配置。Registry 安装要求该范围内已有已发布模块版本。

## 1. 概述

本示例配置双区生产架构：八个子网、两台静态 Web 和两台 App、公网 HTTPS ALB、跨区 MySQL/Redis、一个共享 NAT、TOS、90 天 TLS 与显式监控。相较 basic，增加证书、域名、跨区数据、备份和删除保护配置，支持复用已有网络及数据实例。调用方准备地域依赖、两项密码、入口来源、端点出站、联系人组和归属标签，并完成应用及日志配置。

## 2. 用法

在 `examples/complete` 目录运行。`main.tf` 通过 `terraform-volcenginecc-modules/reference-architecture-web/volcenginecc` 调用远程三层 Web 模块。

使用 Terraform `1.5.7`，准备本目录必填 `terraform.tfvars` 输入、两项敏感密码、两区规格和已预装 Web/App 的镜像。Web 提供 `8080` 和 `/health`，App 提供 `8080`。HTTPS 证书与域名匹配，至少一条监控规则使用已核实的官方指标与联系人组；确认服务、私网端点路由及权限可用。默认完整新建需至少三个公网 EIP 配额，供双区 ALB 与 NAT 使用。

正常部署保持 `deletion_protection=true`、`allow_protection_disable=false`。复用时填全部八个子网 ID，并核对它们与本示例固定 CIDR 的关系；已有 MySQL/Redis 的鉴权、App 子网白名单、备份和保护由调用方维护。

```bash
terraform init
terraform plan -out=部署计划.tfplan
terraform apply 部署计划.tfplan
terraform output -json architecture
```

根据输出配置 DNS、Web 代理、App 的私网 MySQL/Redis 连接、TOS 访问及日志采集。验证 HTTPS、两区 Web → App → 数据层、隔离、共享 NAT 和日志/告警，再运行：

```bash
terraform plan
```

预期为 `No changes`。销毁前先清空 TOS 所有对象、版本和删除标记，在维护窗口同时设置 `deletion_protection=false`、`allow_protection_disable=true`：

```bash
terraform plan -out=关闭保护计划.tfplan
```

审阅计划中的更新和替换，确认只涉及预期资源，再应用保护更新：

```bash
terraform apply 关闭保护计划.tfplan
```

核对 ECS/RDS/Redis/ALB 实际保护已关闭，确认没有已有资源列入销毁范围，然后执行：

```bash
terraform destroy
```

使用独立 State/backend；State、缓存、计划、日志及敏感参数不提交到 Git。

## 3. 依赖要求

| 名称 | 版本 |
|---|---|
| Terraform | `>= 1.5.7, < 1.12.0`；项目固定基线 `= 1.5.7` |
| `volcengine/volcenginecc` | `= 0.0.73` |

这是本目录 `versions.tf` 的实际约束，允许范围比固定基线宽。

## 4. Providers

| 名称 | 来源 |
|---|---|
| `volcenginecc` | `volcengine/volcenginecc` |

本目录配置地域和可选 Cloud Control 端点，无 alias；认证由运行环境提供。

## 5. 资源

| 名称 | 说明 |
|---|---|
| `module.web` | source 为 `terraform-volcenginecc-modules/reference-architecture-web/volcenginecc`，调用远程三层 Web 模块。 |

本目录没有直接 Resource 或 Data Source。默认 ALB、全部新建且仅一条监控规则时，预期由模块管理 37 项资源；包括八个子网、四台静态 ECS、一个 NAT、四个 SNAT 条目及两个 Web/App 路由表。ASG 关闭；复用资源或增加监控规则会改变数量，不包含隐式资源。

## 6. 输入

| 名称 | 说明 |
|---|---|
| `deployment` | 必填对象：`name`、`region`、`zone_a`、`zone_b`、`web_image_id`、`app_image_id`、`web_instance_type`、`app_instance_type`、`key_pair_name`、`database_node_spec`、`bucket_name`、`domain`、`certificate_id` 均为字符串，`allowed_cidrs` 为非空 `set(string)`；两区不重复，证书匹配域名，来源为实际访问出口。 |
| `existing` | 可选对象，默认 `{}`；`vpc_id`、`database_id`、`cache_id` 为可选字符串，默认 null；`subnet_ids` 为可选 `map(string)`，默认 `{}`。复用 VPC 时填完整八个子网，关闭模块 NAT，由调用方维护路由。 |
| `database_password` | 必填敏感字符串，非 null、非空白，通过 `TF_VAR_database_password` 或平台敏感变量提供；复用 MySQL 时仍必填，模块不更新已有密码。 |
| `cache_password` | 必填敏感字符串，非 null、非空白，通过 `TF_VAR_cache_password` 或平台敏感变量提供；复用 Redis 时仍必填，模块不更新已有密码。 |
| `service_egress` | 必填 `map(object({cidr=string, protocol=string, port=number}))`；实际端点 CIDR、tcp/udp、1–65535 整数端口，并具备对应路由。 |
| `monitoring` | 必填非空 `map(object)`，至少一条官方指标规则与已配置联系人组，字段见下文。 |
| `tags` | 必填 `map(string)`，填写所有者与成本归属；Project/Environment 由模块设置。 |
| `load_balancer_kind` | 可选字符串，默认 `"alb"`，支持 alb/clb；两种入口均启用 HTTPS，CLB 的日志与保护限制见第 9 节。 |
| `clb_health_check_cidrs` | 可选 `set(string)`，默认 `[]`；选择 CLB 时必填已核实的 IPv4 来源，当前 Web 安全组仍固定为 `100.64.0.0/10`。 |
| `deletion_protection` | 可选 bool，默认 `true`；正常生产保持开启，维护关闭须同时设置下项。 |
| `allow_protection_disable` | 可选 bool，默认 `false`；只有维护窗口设为 true 才允许关闭保护，不执行销毁。 |
| `cloudcontrol_endpoint` | 可选字符串，默认 `null` 使用 Provider 默认端点；按明确环境要求配置 Cloud Control API 地址。 |

监控完整类型如下。联系人组非空，`evaluation_count >= 1`；namespace/sub_namespace、指标名称、单位、地域和阈值按官方目录核实，规则按模块 Project 标签筛选资源。

```hcl
map(object({
  region = string, namespace = string, sub_namespace = string
  metric_name = string, metric_unit = string, threshold = string
  contact_group_ids = set(string), statistics = optional(string, "avg")
  comparison_operator = optional(string, ">"), evaluation_count = optional(number, 3)
}))
```

VPC 为 `10.20.0.0/16`。primary 的 edge/web/app/data 为 `10.20.0.0/24` 至 `10.20.3.0/24`，secondary 为 `10.20.4.0/24` 至 `10.20.7.0/24`；已有子网 key 为 `primary-edge/web/app/data` 和 `secondary-edge/web/app/data` 的各个组合。其他网段应直接调用根模块。

每区各一台 Web/App，默认 40 GiB ESSD_PL0 系统盘；新建 MySQL 使用跨区双节点、100 GiB 存储及 30 天备份，新建 Redis 使用跨区双节点与每日备份。TLS 保留 90 天，TOS 配置版本控制。模块保护输入为 `deletion_protection || !allow_protection_disable`，因此关闭保护必须同时使用 false/true。

## 7. 输出

| 名称 | 说明 |
|---|---|
| `architecture` | 对象，包含 `network`、`compute`、`entrypoint`、`data`、`storage_and_logs`；用入口地址配置 DNS，用私网接口和数据端点配置应用，用 Bucket/TLS/监控 ID 接入存储、采集与告警；未转发 `nat`。 |

复用 MySQL/Redis 时，`data` 保留 ID，但实例端点为 null，由调用方查询已有服务。

## 8. 示例

本目录即为 complete 示例，适合双区 HTTPS 部署，或在匹配网络中复用数据资源。相较 basic，需要证书、域名、监控及维护保护步骤。

## 9. 说明

凭据通过 `VOLCENGINE_ACCESS_KEY`、`VOLCENGINE_SECRET_KEY` 等 Provider 支持方式注入运行环境，两项密码使用敏感变量；State 仍保存敏感值，由调用方保管。应用、DNS、证书和日志 Agent 由调用方维护；TLS Topic 创建不代表应用日志已自动接入。

已有资源只通过 ID 引用，不 import、不修改其账户、白名单、备份或保护，也不纳入模块 Destroy。新建网络仅为 Web/App 配置 SNAT 和独立路由表；data 使用系统路由表，不配置 SNAT。复用网络时模块 NAT 关闭，已有路由和出站配置由调用方管理。

本示例使用两区静态 ECS，不启用 ASG。ALB 接入 TLS 访问日志与健康检查日志；选择 CLB 时，模块仅传入 TLS 项目和 Topic 关联信息，日志启用开关及 CLB 删除保护由调用方管理。安全组放行业务和显式服务流量，并拒绝未授权出站。

销毁前按第 2 节更新删除保护，并清空 TOS 的对象、历史版本和删除标记。已有资源仍由调用方维护。
