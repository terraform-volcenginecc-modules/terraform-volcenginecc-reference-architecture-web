# Basic Web 架构

单可用区开发示例，包含公网 HTTP CLB、私网 Web/应用 ECS、私网单节点 MySQL/Redis、出站 NAT、私有 TOS 与 TLS 日志。

在 10.20.0.0/16 下规划 27 个 managed resource、四层子网：edge 10.20.0.0/24、web 10.20.1.0/24、app 10.20.2.0/24、data 10.20.3.0/24。一台 Web ECS 和一台应用 ECS 均无公网 EIP。Web/应用使用 SNAT；数据子网不配置 Module 管理的公网默认路由。监听 ACL 限制客户端，Web/应用安全组和数据白名单限制层间流量。CLB 官方服务网段为 100.64.0.0/10。HTTP 和单区数据适用于开发；MySQL 每日备份，Standalone Redis 不支持备份。

调用示例管理 Provider，使用独立内嵌 Module：`source = "./modules/reference-architecture-web"`，无需 Registry Module version。内嵌副本包含根 Module 源码及说明文档。引擎约束为 >= 1.5.7, < 1.12.0，Provider 固定为 0.0.73。

准备已核实的地域/可用区、提供 8080 和 /health 的预装 Web/应用镜像、可用 ECS/RDS 规格、已有密钥对、已开通服务、权限和配额。通过 service_egress 提供实际私网 DNS/TOS/TLS 端点 CIDR，并准备路由；NAT 本身不授予端点访问权限。应用代理/数据连接和日志 Agent 自行配置。

| 输入 | 类型 | 默认值 / 条件 |
|---|---|---|
| `deployment` | object | 必填，字段如下 |
| `database_password` | string, sensitive | 必填，通过平台敏感变量或 TF_VAR_database_password 提供 |
| `cache_password` | string, sensitive | 必填，通过平台敏感变量或 TF_VAR_cache_password 提供 |
| `service_egress` | map(object({cidr=string, protocol=string, port=number})) | 必填，实际 IPv4 CIDR、tcp/udp、整数 1–65535 |
| `tags` | map(string) | {}；Project/Environment 由 Module 设置 |
| `cloudcontrol_endpoint` | string | null，默认线上 API 端点 |

| Deployment 字段 | 类型 | 条件 |
|---|---|---|
| `deployment.name` | string | 必填稳定名称，3–31 位小写字母/数字/连字符，字母开头 |
| `deployment.region` | string | 必填已核实地域 |
| `deployment.zone_id` | string | 必填可用区 |
| `deployment.web_image_id` | string | 必填预装 Web 镜像 |
| `deployment.app_image_id` | string | 必填预装应用镜像 |
| `deployment.web_instance_type` | string | 必填可用 Web 规格 |
| `deployment.app_instance_type` | string | 必填可用应用规格 |
| `deployment.key_pair_name` | string | 必填已有密钥对 |
| `deployment.database_node_spec` | string | 必填可用 MySQL 规格 |
| `deployment.bucket_name` | string | 必填地域唯一 Bucket 名称 |
| `deployment.allowed_cidrs` | set(string) | 必填非空显式客户端 IPv4 CIDR |

实际 deployment/service_egress/tags 已写入 terraform.tfvars。VOLCENGINE_ACCESS_KEY、VOLCENGINE_SECRET_KEY 仅通过环境变量提供，参数文件不含凭据。发布后在 examples/basic 中选择一个引擎及其独立 State 执行：

```bash
terraform init
terraform plan -var-file=terraform.tfvars -out=deployment.tfplan
terraform apply deployment.tfplan
terraform plan -var-file=terraform.tfvars
terraform output -json architecture
```

```bash
tofu init
tofu plan -var-file=terraform.tfvars -out=deployment.tfplan
tofu apply deployment.tfplan
tofu plan -var-file=terraform.tfvars
tofu output -json architecture
```

architecture 对象包含根模块的 network、compute、entrypoint、data、storage_and_logs，不转发 nat。使用 CLB 公网 IP 访问入口，使用私网接口/数据地址配置应用，使用存储/日志 ID 集成服务。此配置的 ASG ID、domain、ALB DNS 为 null，监控 IDs 为空，不输出密码。验证入口和 ACL 拒绝路径、Web 到应用及应用到 MySQL/Redis 的连接、TOS 权限、TLS 日志、二次 Plan No changes。

保留必要数据，清空 Bucket 及所有版本，再销毁并查询 managed resource、服务隐式资源和备份确认彻底移除；State 空不能单独作为依据。

```bash
terraform destroy -var-file=terraform.tfvars
```

```bash
tofu destroy -var-file=terraform.tfvars
```

安全组两阶段维护：沿用 security-group/examples 的“创建后回读，再维护并检查最终 Plan”流程。本模块已显式填写规则十字段，首次创建后平台仍可能附加默认全放通出站。先通过输出的安全组 ID 查询实际规则，再对已创建的 Web/App 安全组执行维护 Plan；确认仅原地删除配置外默认规则、保留业务和 service_egress 规则，且没有新增或替换后，才 Apply。本模块没有 system_default_egress_rules 输入，无需把全放通规则加入期望配置。complete 最终复测在第二阶段维护后，入站/出站十字段校验 4/4 通过。

以下命令适用于调用名 module.web，仅用于首次创建后的定向维护；若地址不同，按实际 State 地址调整。若 Plan 包含创建/替换或安全组仍 tainted，先排查，不能直接应用。维护完成后必须运行无 target 的普通 Plan，并通过云端查询比较完整规则集合；exit 0 才代表整体 No changes。其他资源漂移不能因安全组通过而判定消失。OpenTofu 命令是等价操作说明，真实云维护仅验证了 Terraform 1.5.7。

```bash
terraform plan -var-file=terraform.tfvars \
  -target='module.web.volcenginecc_vpc_security_group.this["web"]' \
  -target='module.web.volcenginecc_vpc_security_group.this["app"]' \
  -out=sg-maintenance.tfplan
terraform apply sg-maintenance.tfplan
terraform plan -var-file=terraform.tfvars -detailed-exitcode
```

```bash
tofu plan -var-file=terraform.tfvars \
  -target='module.web.volcenginecc_vpc_security_group.this["web"]' \
  -target='module.web.volcenginecc_vpc_security_group.this["app"]' \
  -out=sg-maintenance.tfplan
tofu apply sg-maintenance.tfplan
tofu plan -var-file=terraform.tfvars -detailed-exitcode
```

其余限制：创建前用官方 DescribeImages 按 InstanceType 过滤兼容镜像，不能仅按 OS 名选择；最终 complete 使用兼容 Debian10 镜像，两台应用 ECS 创建成功，basic 的镜像不匹配未单独重测。同 VPC 多 NAT 若 ResourceConflict，确认已有网关和在途操作，再重新 Plan；可在审阅后用 -parallelism=1 串行重试，但本轮未验证该方式能使完整部署成功。启动模板 volumes/network_interfaces 回读 null 尚无已验证规避，Web ASG 与 HTTPS 入口仍未通过。RDS public_download_enable=false 实际仍为 true，TOS acl_grant 回读 null（独立 ACL 仅 Owner FULL_CONTROL）；不能用 ignore_changes 将这些差异判为已修复。维护后没有整体 No changes 的证据。

最终复测：basic 计划 27 个资源，23 个对象进入 State，因镜像/规格不匹配未完成部署。原生 Destroy 重试 exit 0；30 个已知对象均不存在，MySQL 补偿后最终 MySQL/Redis 备份均为零。

本地验收证据独立留存。Registry Module 消费及 OpenTofu 云生命周期仍未验证。
