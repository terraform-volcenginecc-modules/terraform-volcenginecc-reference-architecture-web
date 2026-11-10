# Complete Web architecture

A two-zone production baseline with public HTTPS ALB, one private Web ECS and one private application ECS per zone, cross-zone MySQL/Redis, outbound NAT, private versioned TOS, TLS logs and explicit monitoring.

For newly created network/data and one monitoring rule, the plan contains 39 managed resources. The VPC is 10.20.0.0/16; primary edge/web/app/data use 10.20.0.0/24 through 10.20.3.0/24, secondary use 10.20.4.0/24 through 10.20.7.0/24. Web and application ECS each have one node per zone; the Module registers Web ECS directly with the ALB backend. Only the load balancer provides public inbound access; NAT EIPs provide outbound web/app access. Data has no module-managed public default route. Two-node MySQL has 30-day backups, Redis has cross-zone primary/replica backups, TLS retention is 90 days and TOS uses versioning.

This example disables ASG and does not create a launch template, avoiding Provider 0.0.73 returning null for launch-template network_interfaces/volumes. Static Web ECS across two zones does not provide ASG autoscaling.

The example owns Provider configuration and uses its independent embedded Module at `source = "./modules/reference-architecture-web"`. No Registry module version is required. This copy is independent of both the root Module and basic example. Common constraint is >= 1.5.7, < 1.12.0; the Provider is pinned to 0.0.73.

Prepare verified regions/zones and quotas, preinstalled Web/application/log-agent images, available specifications, a key pair, a valid certificate-center ID covering the domain, private service endpoint routes/permissions, official monitoring metrics and existing contact groups. Configure DNS after obtaining the entrypoint. The example does not install applications or create metric autoscaling policies. ALB-to-TLS delivery requires service authorization.

| Input | Type | Default / requirement |
|---|---|---|
| `deployment` | object | Required; fields below |
| `existing` | object | {}; optional reuse fields below |
| `database_password` | string, sensitive | Required through platform sensitive variables or TF_VAR_database_password |
| `cache_password` | string, sensitive | Required through platform sensitive variables or TF_VAR_cache_password |
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

Use terraform.tfvars for non-sensitive inputs. Supply VOLCENGINE_ACCESS_KEY and VOLCENGINE_SECRET_KEY only through environment variables, and passwords through TF_VAR inputs; the parameter file contains no credentials. After publication, choose one engine and independent State in examples/complete:

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

The nonsensitive architecture object forwards network, compute, entrypoint, data and storage_and_logs; it omits nat and passwords. compute.instances contains four static ECS instances and scaling_group_id is null. ALB has DNS and no CLB IP; CLB has no ALB DNS. Use outputs to configure DNS, application/data connections, TOS and log collection. Verify HTTPS/certificate, ingress denial, inter-tier connections, logs, notifications, backup recovery, zone failure and a real No changes plan. The Module manages Web backend registration through static servers.

CLB log enabled/tls_enabled are computed-only in Provider 0.0.73; log bindings do not prove activation. CLB lacks ALB-equivalent deletion protection. Verify official health sources and actual logging/protection separately.

Destroy maintenance: preserve required data and empty all bucket versions. Keep the prod topology and use deletion_protection=false and allow_protection_disable=true for maintenance and destroy. Review the plan first: Provider 0.0.73 plans ALB protection disabling as replacement, so do not directly apply a full plan that replaces a protected ALB. Target the existing ECS/MySQL/Redis and their security-group dependencies, and apply only after confirming in-place updates. Disable deletion protection for the exact ALB in its console, or call the official ModifyLoadBalancerAttributes with its precise LoadBalancerId and DeleteProtection=off. Independently verify ALB/MySQL/Redis protection is disabled.

Then run ordinary destroy. If the Redis allow list returns AllowListBindInstanceCannotDelete, query instance deletion and current allow-list bindings first. If TOS is confirmed NotFound but its asynchronous deletion task remains stalled, stop the current Terraform command and preserve its result. After that command ends, rerun the same destroy so the provider refreshes actual state; never launch concurrent destroys. Verify empty State, then independently query explicit resources, disks, network interfaces, ALB EIPs and backups through native APIs. Do not replace deletion verification with state rm. If final MySQL backups need not be retained, call ModifyBackupPolicy for the exact instance with DataKeepPolicyAfterReleased=None. Disabling retention before destruction can still revert to Last after release; query backups again and, if needed, disable retention for the released instance until backup count is zero. Redis final backups require seven-day retention; query DescribeBackups with Scope=DestroyedInstances rather than treating InstanceNotExist as proof of backup removal.

```bash
terraform destroy -var-file=terraform.tfvars -var=deletion_protection=false -var=allow_protection_disable=true
```

```bash
tofu destroy -var-file=terraform.tfvars -var=deletion_protection=false -var=allow_protection_disable=true
```


Two-stage security-group maintenance follows the security-group/examples workflow: create, read actual rules, maintain, then check the final plan. This module explicitly supplies all ten rule fields, but the platform can still append unrestricted default egress after creation. Query the security-group IDs from outputs, then plan maintenance of the existing Web/App groups. Apply only after confirming in-place removal of unexpected defaults, preservation of business/service_egress rules, and no creation or replacement. This module has no system_default_egress_rules input; adding unrestricted rules to the desired configuration is unnecessary. The final complete retest passed all four ingress/egress ten-field checks after second-stage maintenance.

These commands assume the calling name module.web and are only for targeted maintenance after creation; adjust addresses to actual State when necessary. Investigate any creation, replacement or remaining taint before applying. Afterwards run an ordinary plan without targets and independently compare the complete cloud rule sets; only exit 0 establishes overall No changes. Passing security-group checks does not resolve drift in other resources. OpenTofu commands describe equivalent operations; only Terraform 1.5.7 cloud maintenance was tested.

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

Other limitations: filter official DescribeImages by InstanceType before creation; choosing by OS name alone is insufficient. Reserve EIP quota separately for the public ALB addresses and NAT gateways. For multiple NAT gateways in one VPC, inspect existing gateways and in-flight operations after ResourceConflict, then replan; a reviewed retry with -parallelism=1 can serialize operations. Disabling ASG successfully created four static ECS instances and bypassed launch-template volumes/network_interfaces returning null; the ASG Provider defect itself remains unfixed. RDS public_download_enable=false still reads true, and TOS acl_grant and enable_version_status read null (ACL is Owner FULL_CONTROL only). ignore_changes cannot establish that these differences are fixed.

Static ECS retest: complete planned 39 resources and created 31 State objects. Both Web backends were healthy; Web→application→MySQL queries and Redis read/write passed, while direct Web-to-data access was denied. The full security-group rule sets matched configuration after maintenance. NAT EIP creation failed with QuotaExceeded.Eip, leaving NAT egress unverified; HTTPS still timed out on both ALB public addresses. The second Plan contained eight missing resources and two RDS/TOS updates, so overall deployment and No changes remain unsuccessful.

Local acceptance evidence is retained separately. Registry module consumption and OpenTofu cloud lifecycle remain unverified.
