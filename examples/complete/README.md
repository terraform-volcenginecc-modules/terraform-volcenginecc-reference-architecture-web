# Complete Web architecture

A two-zone production baseline with public HTTPS ALB, balanced Web ASG, private application ECS and cross-zone MySQL/Redis, outbound NAT, private versioned TOS, TLS logs and explicit monitoring.

For newly created network/data and one monitoring rule, the plan contains 39 managed resources. The VPC is 10.20.0.0/16; primary edge/web/app/data use 10.20.0.0/24 through 10.20.3.0/24, secondary use 10.20.4.0/24 through 10.20.7.0/24. Web ASG min/desired/max are 2/2/6; application ECS has one node per zone. Only the load balancer provides public inbound access; NAT EIPs provide outbound web/app access. Data has no module-managed public default route. Two-node MySQL has 30-day backups, Redis has cross-zone primary/replica backups, TLS retention is 90 days and TOS uses versioning.

The example owns Provider configuration and uses `source = "terraform-volcenginecc-modules/reference-architecture-web/volcenginecc"`. This module is unpublished; no release version is invented and Registry installation is unverified. Static validation redirects the source only in temporary copies. Common constraint is >= 1.5.7, < 1.12.0; exact validation engines are Terraform 1.5.7 and OpenTofu 1.11.8 with Registry Provider 0.0.73.

Prepare verified regions/zones and quotas, preinstalled Web/application/log-agent images, available specifications, a key pair, a valid certificate-center ID covering the domain, private service endpoint routes/permissions, official monitoring metrics and existing contact groups. Configure DNS after obtaining the entrypoint. The example does not install applications or create metric autoscaling policies. ALB-to-TLS delivery requires service authorization.

| Input | Type | Default / requirement |
|---|---|---|
| `deployment` | object | Required; fields below |
| `existing` | object | {}; optional reuse fields below |
| `database_password` | string, sensitive | null; required for new MySQL through TF_VAR_database_password |
| `cache_password` | string, sensitive | null; required for new Redis through TF_VAR_cache_password |
| `service_egress` | map(object({cidr=string, protocol=string, port=number})) | Required actual IPv4 endpoint CIDRs, tcp/udp, integer ports 1–65535 |
| `monitoring` | map(object) | Required nonempty official rules; fields below |
| `tags` | map(string) | Required; supply Owner/CostCenter; Project/Environment set by module |
| `load_balancer_kind` | string | "alb"; optional clb with reduced log/protection capability |
| `clb_health_check_cidrs` | set(string) | []; required nonempty official regional sources for clb |
| `deletion_protection` | bool | true |
| `allow_protection_disable` | bool | false; explicit maintenance override |
| `cloudcontrol_endpoint` | string | null; default online API endpoint |

| Field | Type | Default / requirement |
|---|---|---|
| `deployment.name` | string | Required stable name, 3–31 lowercase letters/digits/hyphens, starts with a letter |
| `deployment.region` | string | Required verified region |
| `deployment.zone_a` | string | Required available zone |
| `deployment.zone_b` | string | Required distinct available zone |
| `deployment.web_image_id` | string | Required preinstalled Web image |
| `deployment.app_image_id` | string | Required preinstalled application image |
| `deployment.web_instance_type` | string | Required available specification |
| `deployment.app_instance_type` | string | Required available specification |
| `deployment.key_pair_name` | string | Required existing key pair |
| `deployment.database_node_spec` | string | Required by deployment type, even when reusing MySQL |
| `deployment.bucket_name` | string | Required region-unique name |
| `deployment.allowed_cidrs` | set(string) | Required nonempty client IPv4 CIDRs |
| `deployment.domain` | string | Required HTTPS domain |
| `deployment.certificate_id` | string | Required valid certificate-center ID |
| `existing.vpc_id` | string | null |
| `existing.subnet_ids` | map(string) | {}; required complete primary/secondary -edge/-web/-app/-data keys when reusing a VPC |
| `existing.database_id` | string | null |
| `existing.cache_id` | string | null |
| `monitoring.*.region` | string | Required |
| `monitoring.*.namespace` | string | Required official namespace |
| `monitoring.*.sub_namespace` | string | Required official sub-namespace |
| `monitoring.*.metric_name` | string | Required official metric |
| `monitoring.*.metric_unit` | string | Required official unit |
| `monitoring.*.threshold` | string | Required |
| `monitoring.*.contact_group_ids` | set(string) | Required nonempty existing groups |
| `monitoring.*.statistics` | string | "avg" |
| `monitoring.*.comparison_operator` | string | ">" |
| `monitoring.*.evaluation_count` | number | 3; >= 1 |

Reused networks must match the fixed subnet CIDRs; otherwise invoke the root module with accurate zones. Reuse disables managed NAT and leaves routing with the caller. Existing MySQL/Redis are not imported or modified; verify private endpoint reachability, allow lists, accounts, backups and protection. Their created-endpoint output fields are null; query addresses yourself.

Use private deployment.tfvars and unchanged VOLCENGINE_ACCESS_KEY/VOLCENGINE_SECRET_KEY credentials; passwords use TF_VAR inputs. After publication, choose one engine and independent State in examples/complete:

```bash
terraform init
terraform plan -var-file=deployment.tfvars -out=deployment.tfplan
terraform apply deployment.tfplan
terraform plan -var-file=deployment.tfvars
terraform output -json architecture
```

```bash
tofu init
tofu plan -var-file=deployment.tfvars -out=deployment.tfplan
tofu apply deployment.tfplan
tofu plan -var-file=deployment.tfvars
tofu output -json architecture
```

The nonsensitive architecture object forwards network, compute, entrypoint, data and storage_and_logs; it omits nat and passwords. Web ASG member IDs are cloud-managed. ALB has DNS and no CLB IP; CLB has no ALB DNS. Use outputs to configure DNS, application/data connections, TOS and log collection. Verify HTTPS/certificate, ingress denial, inter-tier connections, logs, notifications, backup recovery, zone failure and a real No changes plan. ASG owns backend registration, without simultaneous static servers.

CLB log enabled/tls_enabled are computed-only in Provider 0.0.73; log bindings do not prove activation. CLB lacks ALB-equivalent deletion protection. Verify official health sources and actual logging/protection separately.

Destroy maintenance: preserve required data and empty all bucket versions. Keep the prod topology and use deletion_protection=false and allow_protection_disable=true for maintenance and destroy. Review the plan first: Provider 0.0.73 plans ALB protection disabling as replacement, so do not directly apply a full plan that replaces a protected ALB. The retest targeted only existing ECS/MySQL/Redis and their security-group dependencies: zero creations, six in-place updates, zero deletions, and a successful apply. This cleanup maintenance does not establish overall deployment success. Disable deletion protection for the exact ALB in its console, or call the official ModifyLoadBalancerAttributes with its precise LoadBalancerId and DeletionProtection=off. Independently verify ALB/MySQL/Redis protection is disabled.

Then run ordinary destroy. If the Redis allow list returns AllowListBindInstanceCannotDelete, query instance deletion and current allow-list bindings first. If TOS is confirmed NotFound but its asynchronous deletion task remains stalled, stop the current Terraform command and preserve its result. After that command ends, rerun the same destroy so the provider refreshes actual state; never launch concurrent destroys. The retest retry exited 0, emptied State, and independently confirmed all 41 known explicit/implicit objects absent. Do not replace deletion verification with state rm. If final MySQL backups need not be retained, call ModifyBackupPolicy for the exact instance with DataKeepPolicyAfterReleased=None and verify zero backups. Redis final backups require seven-day retention and expiry recheck; three known backups currently remain.

```bash
terraform destroy -var-file=deployment.tfvars -var=deletion_protection=false -var=allow_protection_disable=true
```

```bash
tofu destroy -var-file=deployment.tfvars -var=deletion_protection=false -var=allow_protection_disable=true
```


Two-stage security-group maintenance follows the security-group/examples workflow: create, read actual rules, maintain, then check the final plan. This module explicitly supplies all ten rule fields, but the platform can still append unrestricted default egress after creation. Query the security-group IDs from outputs, then plan maintenance of the existing Web/App groups. Apply only after confirming in-place removal of unexpected defaults, preservation of business/service_egress rules, and no creation or replacement. This module has no system_default_egress_rules input; adding unrestricted rules to the desired configuration is unnecessary. The final complete retest passed all four ingress/egress ten-field checks after second-stage maintenance.

These commands assume the calling name module.web and are only for targeted maintenance after creation; adjust addresses to actual State when necessary. Investigate any creation, replacement or remaining taint before applying. Afterwards run an ordinary plan without targets and independently compare the complete cloud rule sets; only exit 0 establishes overall No changes. Passing security-group checks does not resolve drift in other resources. OpenTofu commands describe equivalent operations; only Terraform 1.5.7 cloud maintenance was tested.

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

Other limitations: filter official DescribeImages by InstanceType before creation; choosing by OS name alone is insufficient. The final complete retest used compatible Debian10 images and created both application ECS instances; basic image mismatch was not separately retested. For multiple NAT gateways in one VPC, inspect existing gateways and in-flight operations after ResourceConflict, then replan. A reviewed retry with -parallelism=1 can serialize operations, but this retest did not verify that it completes the deployment. There is no verified workaround for launch-template volumes/network_interfaces returning null; Web ASG and HTTPS entry remain unsuccessful. RDS public_download_enable=false still reads true, and TOS acl_grant reads null (independent ACL is Owner FULL_CONTROL only). ignore_changes cannot establish that these differences are fixed. No overall post-maintenance No changes evidence exists.

Final retest: complete planned 39 resources, created 29 State objects, and passed second-stage security-group maintenance. Redis AUTH/SET/GET/DEL passed on both application instances; the custom MySQL probe failed authentication and HTTPS timed out. The cause of MySQL authentication failure requires independent client verification. Cleanup retry confirmed 41 objects absent; final Redis backups remain.

Local acceptance evidence is retained separately. Registry module consumption and OpenTofu cloud lifecycle remain unverified.
