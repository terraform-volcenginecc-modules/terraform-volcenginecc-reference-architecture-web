# Complete Web 架构

双可用区生产基线，包含公网 HTTPS ALB、每区一台私网 Web ECS、每区一台私网应用 ECS 和跨区 MySQL/Redis、出站 NAT、私有版本化 TOS、TLS 日志及显式监控。

新建网络/数据且一条监控规则时，Plan 包含 39 个 managed resource。VPC 为 10.20.0.0/16；primary edge/web/app/data 使用 10.20.0.0/24 至 10.20.3.0/24，secondary 使用 10.20.4.0/24 至 10.20.7.0/24。Web 和应用 ECS 均为每区一台，Web ECS 由 Module 直接注册到 ALB 后端。仅负载均衡提供公网入站，NAT EIP 提供 Web/应用出站，数据层无 Module 管理的公网默认路由。双节点 MySQL 备份保留 30 天，Redis 为跨区主从备份，TLS 保留 90 天，TOS 开启版本控制。

本示例禁用 ASG，不创建启动模板，以避开 Provider 0.0.73 对启动模板 network_interfaces/volumes 回读为 null 的缺陷。双区静态 Web ECS 不具备 ASG 的自动扩缩容能力。

示例管理 Provider 配置，使用独立内嵌 Module：`source = "./modules/reference-architecture-web"`，无需 Registry Module version。此副本与根 Module、basic 内嵌副本相互独立。共同约束为 >= 1.5.7, < 1.12.0，Provider 固定为 0.0.73。

准备已核实地域/可用区和配额、预装 Web/应用/日志 Agent 镜像、可用规格、密钥对、覆盖域名的有效证书中心 ID、私网服务端点路由/权限、官方监控指标及已有联系人组。获取入口后配置 DNS。示例不安装应用、不创建指标伸缩策略。ALB 投递 TLS 需服务授权。

| 输入 | 类型 | 默认值 / 条件 |
|---|---|---|
| `deployment` | object | 必填，字段如下 |
| `existing` | object | {}，可选复用字段如下 |
| `database_password` | string, sensitive | 必填，通过平台敏感变量或 TF_VAR_database_password 提供 |
| `cache_password` | string, sensitive | 必填，通过平台敏感变量或 TF_VAR_cache_password 提供 |
| `service_egress` | map(object({cidr=string, protocol=string, port=number})) | 必填实际 IPv4 端点 CIDR、tcp/udp、整数端口 1–65535 |
| `monitoring` | map(object) | 必填非空官方规则，字段如下 |
| `tags` | map(string) | 必填，提供 Owner/CostCenter；Project/Environment 由 Module 设置 |
| `load_balancer_kind` | string | "alb"；可选 clb，日志/保护能力较少 |
| `clb_health_check_cidrs` | set(string) | []；clb 时必填非空地域官方来源 |
| `deletion_protection` | bool | true |
| `allow_protection_disable` | bool | false，显式维护开关 |
| `cloudcontrol_endpoint` | string | null，默认线上 API 端点 |

| 字段 | 类型 | 默认值 / 条件 |
|---|---|---|
| `deployment.name` | string | 必填稳定名称，3–31 位小写字母/数字/连字符，字母开头 |
| `deployment.region` | string | 必填已核实地域 |
| `deployment.zone_a` | string | 必填可用区 |
| `deployment.zone_b` | string | 必填不同可用区 |
| `deployment.web_image_id` | string | 必填预装 Web 镜像 |
| `deployment.app_image_id` | string | 必填预装应用镜像 |
| `deployment.web_instance_type` | string | 必填可用规格 |
| `deployment.app_instance_type` | string | 必填可用规格 |
| `deployment.key_pair_name` | string | 必填已有密钥对 |
| `deployment.database_node_spec` | string | deployment 类型必填，复用 MySQL 时也需提供 |
| `deployment.bucket_name` | string | 必填地域唯一名称 |
| `deployment.allowed_cidrs` | set(string) | 必填非空客户端 IPv4 CIDR |
| `deployment.domain` | string | 必填 HTTPS 域名 |
| `deployment.certificate_id` | string | 必填有效证书中心 ID |
| `existing.vpc_id` | string | null |
| `existing.subnet_ids` | map(string) | {}；复用 VPC 时须提供完整 primary/secondary -edge/-web/-app/-data key |
| `existing.database_id` | string | null |
| `existing.cache_id` | string | null |
| `monitoring.*.region` | string | 必填 |
| `monitoring.*.namespace` | string | 必填官方 namespace |
| `monitoring.*.sub_namespace` | string | 必填官方 sub-namespace |
| `monitoring.*.metric_name` | string | 必填官方指标 |
| `monitoring.*.metric_unit` | string | 必填官方单位 |
| `monitoring.*.threshold` | string | 必填 |
| `monitoring.*.contact_group_ids` | set(string) | 必填非空已有联系人组 |
| `monitoring.*.statistics` | string | "avg" |
| `monitoring.*.comparison_operator` | string | ">" |
| `monitoring.*.evaluation_count` | number | 3；>= 1 |

复用网络必须匹配固定子网 CIDR，否则直接调用根 Module 并提供准确 zones。复用关闭 managed NAT，路由归调用方管理。已有 MySQL/Redis 不 import、不修改，须确认私网端点连通、白名单、账户、备份和保护；对应新建端点输出为 null，地址自行查询。

非敏感输入已写入 terraform.tfvars。VOLCENGINE_ACCESS_KEY、VOLCENGINE_SECRET_KEY 仅通过环境变量提供，密码通过 TF_VAR 提供，参数文件不含凭据。发布后在 examples/complete 中选择一个引擎和独立 State：

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

非敏感 architecture 对象转发 network、compute、entrypoint、data、storage_and_logs，不包含 nat 和密码。compute.instances 输出四台静态 ECS，scaling_group_id 为 null；ALB 有 DNS、无 CLB IP，CLB 无 ALB DNS。通过输出配置 DNS、应用/数据连接、TOS 和日志采集。验证 HTTPS/证书、入站拒绝、层间连接、日志、通知、备份恢复、可用区故障及真实 No changes。Web 后端由 Module 的静态 servers 配置管理。

Provider 0.0.73 的 CLB 日志 enabled/tls_enabled 为 computed-only，绑定日志不能证明已开启。CLB 无与 ALB 等价的删除保护，须单独核实官方健康来源及实际日志/保护。

销毁维护：保留必要数据并清空 Bucket 所有版本，保持 prod 拓扑，将 deletion_protection=false、allow_protection_disable=true 用于维护和后续 Destroy。先审阅维护 Plan；Provider 0.0.73 对 ALB 关闭保护会计划替换，不要直接应用包含受保护 ALB 替换的整体 Plan。对已存在 ECS/MySQL/Redis 及其安全组依赖执行定向维护，确认仅原地更新后再 Apply。通过 ALB 控制台关闭本次实例删除保护，或对精确 LoadBalancerId 调用官方 ModifyLoadBalancerAttributes 将 DeleteProtection 设为 off，再独立回查 ALB/MySQL/Redis 保护均已关闭。

随后执行普通 Destroy。若 Redis 白名单报 AllowListBindInstanceCannotDelete，先查询确认实例已删除及白名单当前绑定；若 TOS 已确认 NotFound 但异步删除任务持续挂起，停止当前 Terraform 命令并保存结果。前一命令结束后，重新执行相同 Destroy，让 Provider 刷新实际状态；禁止并行启动第二个 Destroy。确认 State 为空，并通过原生 API 独立回查显式资源、云盘、网卡、ALB EIP 和备份。不要使用 state rm 代替删除确认。MySQL 最终备份如无需保留，对精确实例调用 ModifyBackupPolicy，设置 DataKeepPolicyAfterReleased=None；销毁前关闭保留仍可能在释放后恢复为 Last，应再次查询备份，必要时对已释放实例重新关闭保留，直到备份数为零。Redis 最终备份强制保留七天，须用 DescribeBackups 的 Scope=DestroyedInstances 回查，不能以 InstanceNotExist 判定备份已清空。

```bash
terraform destroy -var-file=terraform.tfvars -var=deletion_protection=false -var=allow_protection_disable=true
```

```bash
tofu destroy -var-file=terraform.tfvars -var=deletion_protection=false -var=allow_protection_disable=true
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

其余限制：创建前用官方 DescribeImages 按 InstanceType 过滤兼容镜像，不能仅按 OS 名选择。为 ALB 公网地址和 NAT EIP 分别预留配额。同 VPC 多 NAT 若 ResourceConflict，确认已有网关和在途操作，再重新 Plan；可在审阅后用 -parallelism=1 串行重试。禁用 ASG 已通过四台静态 ECS 的真实创建验证，可避开启动模板 volumes/network_interfaces 回读 null；ASG 本身的 Provider 缺陷仍未修复。RDS public_download_enable=false 实际仍为 true，TOS acl_grant 和 enable_version_status 回读 null（ACL 仅 Owner FULL_CONTROL）；不能用 ignore_changes 将这些差异判为已修复。

静态 ECS 复测：complete 计划 39 个资源，31 个对象进入 State；两台 Web 后端健康，Web→应用→MySQL 查询及 Redis 读写通过，Web 直连数据层被拒绝。安全组维护后完整规则集合匹配配置。NAT EIP 创建因 QuotaExceeded.Eip 失败，NAT 出站未验证；ALB 两个公网地址的 HTTPS 仍超时。二次 Plan 包含 8 项未创建资源及 RDS/TOS 两项更新，整体部署和 No changes 均未通过。

本地验收证据独立留存。Registry Module 消费及 OpenTofu 云生命周期仍未验证。
