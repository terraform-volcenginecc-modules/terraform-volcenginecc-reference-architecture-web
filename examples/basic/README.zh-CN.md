# BASIC Web 架构 示例

## 1. 概述

本示例创建单区开发环境：四层子网、公网 HTTP CLB、一台 Web 和一台 App、私网单节点 MySQL/Redis、一个出站 NAT、TOS 与 TLS。相较 complete，不配置双区、HTTPS、监控和生产删除保护。调用方准备可用区、预装服务的镜像、规格、密钥对、Bucket 名称、两项密码、入口来源及服务出站规则；应用连接和日志采集由调用方配置。

## 2. 用法

在 `examples/basic` 目录运行。`main.tf` 通过 `terraform-volcenginecc-modules/reference-architecture-web/volcenginecc` 调用远程三层 Web 模块。

使用 Terraform `1.5.7`，准备本目录 `terraform.tfvars` 中的必填输入和两项敏感密码。镜像需提供 Web `8080`、`/health` 和 App `8080`；确认目标地域服务已开通、规格可用、私网端点路由及权限具备。完整新建需至少两个公网 EIP 配额，分别供 CLB 和 NAT 使用。入口白名单填实际访问请求的公网出口 CIDR。

```bash
terraform init
terraform plan -out=部署计划.tfplan
terraform apply 部署计划.tfplan
terraform output -json architecture
```

使用输出配置 Web 代理、App 的 MySQL/Redis 连接、TOS 访问及日志 Agent。依次验证公网 HTTP、Web → App → MySQL/Redis、Web 数据层隔离和显式 NAT 出站，再运行：

```bash
terraform plan
```

预期为 `No changes`。需要销毁时，核对销毁范围，清空 Bucket 的对象、历史版本和删除标记；如另行开启删除保护，先关闭并应用更新后再执行：

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

本目录配置地域和可选 Cloud Control 端点，无 alias；凭据由运行环境提供。

## 5. 资源

| 名称 | 说明 |
|---|---|
| `module.web` | source 为 `terraform-volcenginecc-modules/reference-architecture-web/volcenginecc`，调用远程三层 Web 模块。 |

本目录没有直接声明 Resource 或 Data Source。完整新建预期由模块管理 27 项资源：包括一台 Web、一台 App、四个子网、两个 SNAT 条目和一个 Web/App 路由表；ASG 关闭，不包含云服务隐式资源。

## 6. 输入

| 名称 | 说明 |
|---|---|
| `deployment` | 必填对象：`name`、`region`、`zone_id`、`web_image_id`、`app_image_id`、`web_instance_type`、`app_instance_type`、`key_pair_name`、`database_node_spec`、`bucket_name` 均为字符串，`allowed_cidrs` 为非空 `set(string)`；填写目标地域真实依赖和入口来源。 |
| `database_password` | 必填敏感字符串，非 null、非空白；通过 `TF_VAR_database_password` 或平台敏感变量提供，满足 MySQL 密码规则。 |
| `cache_password` | 必填敏感字符串，非 null、非空白；通过 `TF_VAR_cache_password` 或平台敏感变量提供，满足 Redis 密码规则。 |
| `service_egress` | 必填 `map(object({cidr=string, protocol=string, port=number}))`；按实际 DNS/TOS/TLS 等端点填写，CIDR 合法、协议 tcp/udp、端口为 1–65535 的整数，并准备对应路由。 |
| `tags` | 可选 `map(string)`，默认 `{}`；填写 Owner/CostCenter 等标签，Project/Environment 由模块设置。 |
| `cloudcontrol_endpoint` | 可选字符串，默认 `null` 使用 Provider 默认端点；仅在明确需要时设置 Cloud Control API 地址。 |

VPC 固定为 `10.20.0.0/16`，primary 的 edge/web/app/data 分别为 `10.20.0.0/24` 至 `10.20.3.0/24`。本示例没有已有资源复用输入。Web/App 均每区一台、40 GiB ESSD_PL0 系统盘，MySQL 默认 100 GiB、7 天备份；开发 Redis 为单节点，不配置备份。CLB 与 NAT 默认带宽各 10 Mbps，TLS 默认保留 30 天。

## 7. 输出

| 名称 | 说明 |
|---|---|
| `architecture` | 对象，包含 `network`、`compute`、`entrypoint`、`data`、`storage_and_logs`；使用私网接口和数据端点配置应用，使用 CLB 公网地址访问入口，使用 Bucket/TLS ID 配置存储与采集；未转发根模块 `nat`。 |

## 8. 示例

本目录即为 basic 示例，适合单区开发及最小三层链路验证。需要双区、HTTPS、跨区数据实例和监控时使用 complete，并准备其额外输入。

## 9. 说明

凭据通过 `VOLCENGINE_ACCESS_KEY`、`VOLCENGINE_SECRET_KEY` 等 Provider 支持的运行环境方式注入，密码使用敏感变量；State 仍保存敏感值，应由调用方保管。应用安装、连接、日志 Agent 和私网运维通道由调用方准备，没有默认 SSH 入站规则。

CLB HTTP 监听器通过后端组访问 Web `8080`，健康检查省略覆盖端口并随从后端。Web 安全组来源固定为 `100.64.0.0/10`；服务出站仅放行显式规则，优先级 99 的拒绝阻止平台优先级 100 的默认允许规则。单一入口 CIDR 只放行对应出口，换网络或多人访问要维护白名单。

NAT 只为 Web/App 建立 SNAT 和独立路由表，默认路由指向共享 NAT。data 使用系统路由表，不配置 SNAT。

CLB 仅传入 TLS 项目和 Topic 关联信息，日志启用开关由调用方管理；模块不配置 CLB 删除保护。销毁前清空 TOS 的对象、历史版本和删除标记。
