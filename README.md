# terraform-volcenginecc-reference-architecture-web

A composable Volcengine Web infrastructure module with layered networking, a load balancer, Web/application compute, private MySQL/Redis, object storage, logs and monitoring.

## 1. Overview

The module supports single-zone development and multiple-zone production environments. It creates VPC/subnets, security groups, ECS or Web ASG, ALB/CLB, RDS MySQL, Redis, TOS, TLS and optional CloudMonitor rules. Existing network and data resources remain owned by the caller; providing IDs does not import them.

Each zone has edge, web, app and data subnets. Only the load balancer exposes an inbound public entrypoint. ECS has no public EIP; NAT provides optional outbound access for web/app subnets. Data subnets have no module-managed public default route. Application installation, proxy/database configuration, DNS, certificates, service identities and log agents are caller responsibilities. The requested CLS capability uses Volcengine TLS.

**Final cloud retest: partial success; full acceptance remains incomplete.** Security-group maintenance passed 4/4 complete-rule checks. Both complete application ECS instances and Redis operations succeeded. Launch-template readback, NAT concurrency, RDS/TOS drift and unverified business paths remain; cleanup retry removed instances/network, with three Redis final backups awaiting expiry checks.

## 2. Usage

Configure the provider, region, credentials and backend in the calling root. Supply verified zone IDs, preinstalled Web/application images, instance specifications, an existing ECS key pair, RDS specification, a region-unique bucket name and explicit ingress CIDRs. Enable the required services and confirm quotas and permissions. Web images must serve the configured health path.

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

This minimal invocation uses a private HTTP ALB. Supply actual private DNS/TOS/TLS endpoint CIDRs through `service_egress`; routes, service permissions and application configuration must exist. Credentials use `VOLCENGINE_ACCESS_KEY` and `VOLCENGINE_SECRET_KEY` without decoding. Supply passwords through `TF_VAR_database_password` and `TF_VAR_cache_password`. Keep real credentials and deployment inputs outside Git.

The Registry source identifies this Web module, following the naming pattern `terraform-volcenginecc-modules/vpc/volcenginecc`. This module is unpublished; no release version is invented and Registry installation is unverified. Local acceptance used isolated copies pointing to the tested module.

After publication, run one engine in a dedicated calling directory with verified `deployment.tfvars`. Review costs and permissions before applying.

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

Use separate State, lock files and caches for engine validation. The application consumes private compute/data endpoints and storage/log IDs. Verify entrypoint access, inter-tier connections, logs and alerts, followed by a second plan reporting No changes.

## 3. Examples

| Example directory | Scenario | Network and compute | Entry, data and operations |
|---|---|---|---|
| examples/basic | Single-zone development, minimal three-tier Web | Four subnets, one Web ECS and one application ECS, one outbound NAT | Public HTTP CLB with ACL; private single-node MySQL/Redis; private TOS, TLS, MySQL backup; standalone Redis has no backup support |
| examples/complete | Multiple-zone production baseline | Eight subnets, balanced Web ASG, one application ECS per zone, one outbound NAT per zone for a new VPC | Public HTTPS ALB, certificate/domain, cross-zone MySQL/Redis, ALB logs, 90-day TLS, explicit monitoring, 30-day MySQL backups, Redis backups, TOS versioning, protection and ownership/cost tags |

Complete accepts existing network/database/cache IDs and an optional CLB entry. Its fixed subnet CIDRs must match reused networks. Reused network routing/NAT and data authentication, allow lists, backups and protection remain caller-owned. CLB log/protection limitations appear in Notes. ASG does not create metric scaling policies.

## 4. Requirements

| Requirement | Value |
|---|---|
| Common engine constraint | >= 1.5.7, < 1.12.0 |
| Exact validation engines | Terraform 1.5.7 and OpenTofu 1.11.8; other versions in the range are unverified |
| Minimum provider | volcengine/volcenginecc >= 0.0.73 |
| Validation/example provider | Registry release 0.0.73 |
| Networking | Distinct zones, nonoverlapping IPv4 subnets contained in the VPC CIDR |
| Production | At least two zones, HTTPS, logs and deletion protection unless an explicit maintenance override is set; ASG min at least the zone count |
| External prerequisites | Enabled services, quotas, images, instance specifications, key pair, endpoint routes/permissions; HTTPS certificate/domain and official monitoring metrics/contact groups where used |

## 5. Providers

| Name | Source | Constraint | Documentation |
|---|---|---|---|
| volcenginecc | volcengine/volcenginecc | Root >= 0.0.73; examples and validation = 0.0.73 | [Registry](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs) |

There is no provider configuration in the reusable root module. Preserve the caller's lock file; static validation uses independent locks/caches and direct Registry installation without development overrides. No other cloud provider, data source, provisioner or script resource is used.

## 6. Resources

All rows use managed resources. Counts below assume newly created network/data and one complete monitoring rule. Basic plans 27 resources; complete plans 39. Cloud-managed ASG members and implicit service resources are not included in these counts.

| Resource type | Address name | Basic / complete | Responsibility and official documentation |
|---|---|---|---|
| `volcenginecc_vpc_vpc` | this | 1 / 1 | [VPC](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/vpc_vpc); optional reuse |
| `volcenginecc_vpc_subnet` | this | 4 / 8 | [Layered subnets](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/vpc_subnet); optional complete reuse |
| `volcenginecc_vpc_security_group` | this | 2 / 2 | [Web/app traffic matrix](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/vpc_security_group) |
| `volcenginecc_ecs_instance` | this | 2 / 2 | [Private compute](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/ecs_instance); complete static instances are application nodes |
| `volcenginecc_ecs_launch_template` | web | 0 / 1 | [ASG template](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/ecs_launch_template) |
| `volcenginecc_autoscaling_scaling_group` | web | 0 / 1 | [Web capacity and registration](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/autoscaling_scaling_group) |
| `volcenginecc_alb_load_balancer` | this | 0 / 1 | [ALB](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/alb_load_balancer) |
| `volcenginecc_alb_acl` | this | 0 / 1 | [ALB ingress ACL](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/alb_acl) |
| `volcenginecc_alb_listener` | this | 0 / 1 | [HTTP/HTTPS listener](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/alb_listener) |
| `volcenginecc_alb_server_group` | this | 0 / 1 | [Web backend group](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/alb_server_group) |
| `volcenginecc_clb_clb` | this | 1 / 0 | [Alternative CLB](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/clb_clb) |
| `volcenginecc_clb_acl` | this | 1 / 0 | [CLB ingress ACL](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/clb_acl) |
| `volcenginecc_clb_listener` | this | 1 / 0 | [CLB listener](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/clb_listener) |
| `volcenginecc_clb_server_group` | this | 1 / 0 | [CLB Web backends](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/clb_server_group) |
| `volcenginecc_natgateway_ngw` | this | 1 / 2 | [Outbound NAT](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/natgateway_ngw) |
| `volcenginecc_vpc_eip` | nat | 1 / 2 | [NAT outbound EIP](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/vpc_eip) |
| `volcenginecc_natgateway_snatentry` | this | 2 / 4 | [Web/app SNAT](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/natgateway_snatentry) |
| `volcenginecc_vpc_route_table` | private | 1 / 2 | [Web/app default routes](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/vpc_route_table); no data association or DNAT |
| `volcenginecc_rdsmysql_instance` | this | 1 / 1 | [Private MySQL](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/rdsmysql_instance); optional reuse |
| `volcenginecc_rdsmysql_allow_list` | this | 1 / 1 | [Application CIDR allow list](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/rdsmysql_allow_list) |
| `volcenginecc_redis_instance` | this | 1 / 1 | [Authenticated private Redis](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/redis_instance); optional reuse |
| `volcenginecc_redis_allow_list` | this | 1 / 1 | [Application CIDR allow list](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/redis_allow_list) |
| `volcenginecc_tos_bucket` | this | 1 / 1 | [Private bucket](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/tos_bucket); production versioning |
| `volcenginecc_tls_project` | this | 1 / 1 | [Log project](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/tls_project) |
| `volcenginecc_tls_topic` | this | 3 / 3 | [Application/access/health topics](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/tls_topic) |
| `volcenginecc_cloudmonitor_rule` | this | 0 / 1 | [Explicit metric alerts](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs/resources/cloudmonitor_rule); one per input key |

| Source | Destination | Port | Control |
|---|---|---|---|
| Explicit client CIDRs | Load balancer | 80/443 | Listener ACL |
| Official ALB/CLB forwarding range 100.64.0.0/10 | Web | TCP web_port, default 8080 | Web security-group ingress; CLB does not bypass SG |
| Web subnets | Application | TCP app_port, default 8080 | Web egress and application ingress |
| Application subnets | Data subnets | TCP 3306/6379 | Application egress and database/cache allow lists |
| Web/application | Explicit service endpoints | Supplied TCP/UDP port | service_egress and caller-managed service routes |

No SSH ingress is configured. Provider 0.0.73 can append unrestricted default egress on creation; complete second-stage maintenance removed it and passed 4/4 full-rule checks. Follow the maintenance procedure in Notes and verify independently.

## 7. Inputs

`object` and `map(object)` fields are fully listed below. A required field has no default; optional defaults are applied by the module. Top-level `null` means no creation configuration or no existing ID, depending on the input.

| Name | Type | Default | Required / description |
|---|---|---|---|
| `name` | string | none | Required; 3–31 lowercase letters/digits/hyphens, starts with a letter; Project tag |
| `environment` | string | "dev" | dev or prod; production enforces topology/HTTPS/logs/protection |
| `tags` | map(string) | {} | Project/Environment are overridden by module values |
| `vpc_cidr` | string | "10.20.0.0/16" | IPv4; must also describe the reused VPC accurately |
| `zones` | map(object) | none | Required; stable keys, distinct zone IDs and four nonoverlapping contained CIDRs |
| `existing_vpc_id` | string | null | Reuse requires every existing_subnet_ids entry; NAT must be disabled |
| `existing_subnet_ids` | map(string) | {} | Exact keys: zone key plus -edge/-web/-app/-data |
| `web` | object | none | Required; preinstalled image and instance type |
| `app` | object | none | Required; preinstalled image and instance type |
| `key_pair_name` | string | none | Required; existing key pair, private maintenance path |
| `web_port` | number | 8080 | Integer 1–65535 |
| `app_port` | number | 8080 | Integer 1–65535 |
| `load_balancer` | object | none | Required; nonempty allowed_cidrs, default private ALB |
| `autoscaling` | object | {} | Optional Web ASG; replaces static Web ECS |
| `existing_database_id` | string | null | Exactly one of this ID or database; caller owns reused service settings |
| `database` | object | null | Required for new MySQL; mutually exclusive with existing_database_id |
| `database_password` | string, sensitive | null | Required for new MySQL; sensitive values remain in State |
| `existing_cache_id` | string | null | Exactly one of this ID or cache; caller owns reused service settings |
| `cache` | object | null | Required for new Redis; {} uses field defaults |
| `cache_password` | string, sensitive | null | Required for new Redis; no password-free access |
| `bucket_name` | string | none | Required; 3–63 lowercase letters/digits/hyphens, alphanumeric ends, region-unique |
| `enable_logs` | bool | true | Production requires true |
| `log_retention_days` | number | 30 | Integer 1–3650 |
| `deletion_protection` | bool | false | Production requires true unless maintenance override permits disabling |
| `allow_protection_disable` | bool | false | Explicit maintenance override; does not destroy resources |
| `monitoring` | map(object) | {} | Official metrics/contact groups; complete requires at least one rule |
| `service_egress` | map(object) | {} | Actual IPv4 endpoint CIDRs and explicit TCP/UDP ports |
| `nat` | object | {} | Per-zone outbound NAT for newly created networks only |

| Field | Type | Default | Requirement / meaning |
|---|---|---|---|
| `zones.*.zone_id` | string | none | Required |
| `zones.*.edge_cidr` | string | none | Required IPv4 CIDR |
| `zones.*.web_cidr` | string | none | Required IPv4 CIDR |
| `zones.*.app_cidr` | string | none | Required IPv4 CIDR |
| `zones.*.data_cidr` | string | none | Required IPv4 CIDR |
| `web.image_id` | string | none | Required preinstalled Web image |
| `web.instance_type` | string | none | Required available specification |
| `web.count_per_zone` | number | 1 | Optional integer 1–1024; ignored for Web ASG capacity |
| `web.disk_size` | number | 40 | Optional; at least 40 GiB |
| `web.disk_type` | string | "ESSD_PL0" | Optional |
| `app.image_id` | string | none | Required preinstalled application image |
| `app.instance_type` | string | none | Required available specification |
| `app.count_per_zone` | number | 1 | Optional integer 1–1024 |
| `app.disk_size` | number | 40 | Optional; at least 40 GiB |
| `app.disk_type` | string | "ESSD_PL0" | Optional |
| `load_balancer.kind` | string | "alb" | Optional alb/clb |
| `load_balancer.public` | bool | false | Optional public inbound entry |
| `load_balancer.https` | bool | false | Optional; production requires true |
| `load_balancer.certificate_id` | string | null | Required with HTTPS; certificate-center ID |
| `load_balancer.domain` | string | null | Required with HTTPS; caller configures DNS |
| `load_balancer.allowed_cidrs` | set(string) | none | Required nonempty IPv4 set |
| `load_balancer.health_check_cidrs` | set(string) | [] | Required nonempty official sources for CLB |
| `load_balancer.health_path` | string | "/health" | Optional; starts with / |
| `load_balancer.bandwidth` | number | 10 | Optional; at least 1 Mbps |
| `load_balancer.clb_spec` | string | "small_1" | Optional CLB specification |
| `autoscaling.enabled` | bool | false | Optional |
| `autoscaling.min` | number | 2 | Optional integer >= 1; production >= zone count |
| `autoscaling.desired` | number | 2 | Optional integer; min <= desired <= max |
| `autoscaling.max` | number | 6 | Optional integer |
| `database.node_spec` | string | none | Required when database is supplied |
| `database.engine_version` | string | "MySQL_8_0" | Optional |
| `database.storage_space` | number | 100 | Optional; at least 20 GiB |
| `database.storage_type` | string | "CloudESSD_PL0" | Optional |
| `database.account_name` | string | "webadmin" | Optional super account |
| `database.backup_retention_days` | number | 7 | Optional; 7–3650 days |
| `cache.engine_version` | string | "6.0" | Optional |
| `cache.shard_capacity` | number | 1024 | Optional; at least 256 MiB |
| `cache.backup_hour` | number | 3 | Optional integer 0–23, UTC+8; standalone has no backup |
| `monitoring.*.region` | string | none | Required |
| `monitoring.*.namespace` | string | none | Required official metric namespace |
| `monitoring.*.sub_namespace` | string | none | Required official sub-namespace |
| `monitoring.*.metric_name` | string | none | Required official metric |
| `monitoring.*.metric_unit` | string | none | Required official unit |
| `monitoring.*.threshold` | string | none | Required |
| `monitoring.*.contact_group_ids` | set(string) | none | Required nonempty existing contact groups |
| `monitoring.*.statistics` | string | "avg" | Optional |
| `monitoring.*.comparison_operator` | string | ">" | Optional |
| `monitoring.*.evaluation_count` | number | 3 | Optional; >= 1 |
| `service_egress.*.cidr` | string | none | Required IPv4 CIDR |
| `service_egress.*.protocol` | string | none | Required tcp/udp |
| `service_egress.*.port` | number | none | Required integer 1–65535 |
| `nat.enabled` | bool | false | Optional; cannot enable with an existing VPC |
| `nat.bandwidth` | number | 10 | Optional; 1–200 Mbps |

## 8. Outputs

`compute.instances.*.network_interface` is an object with string fields network_interface_id, mac_address, primary_ip_address, subnet_id and vpc_id; number ipv_6_address_count; and set(string) fields ipv_6_addresses, private_ip_addresses and security_group_ids. `data.mysql_endpoints` is set(object), with endpoint_id, endpoint_name, connection_mode and read_write_mode strings and an addresses set(object). Each address includes domain, ip_address, port, network_type, subnet_id, eip_id and internet_protocol strings plus dns_visibility/eip_locked booleans. Other endpoint settings follow the linked RDS schema. The Redis private address is a domain string. CLB IP is null for ALB; for a private CLB its absence/value follows provider readback.

All outputs are nonsensitive objects; resource IDs are owned by the module unless explicitly reused. Endpoint/interface collections follow the Provider 0.0.73 schema, with fields computed during creation. No passwords are output.

| Name | Type / fields | Meaning and null conditions |
|---|---|---|
| `network` | object: vpc_id string, subnet_ids map(string), security_group_ids map(string) | Stable logical keys; reused VPC/subnets remain caller-owned |
| `nat` | object of map(string): gateway_ids, eip_ids, snat_ids, route_table_ids | Each field is {} when disabled; this output is declared in outputs.tf |
| `compute` | object: instances map(object({id=string, network_interface=provider object})), scaling_group_id string or null | ASG ID null when disabled; cloud manages ASG members; static application instances remain present |
| `entrypoint` | object: id/server_group_id string, domain/alb_dns_name/clb_public_ip string or null | domain null without a supplied domain; ALB DNS null for CLB; CLB IP null for ALB, private CLB follows provider readback; DNS records are caller-owned |
| `data` | object: database_id/cache_id string, mysql_endpoints set(object) or null, redis_private_address string or null | Created private endpoints; corresponding endpoint field null when reusing that service; caller queries reused addresses |
| `storage_and_logs` | object: bucket_name string, tls_project_id string or null, topic_ids/monitoring_rule_ids map(string) | Log project null and topics {} when logs disabled; monitoring IDs {} with no rules |

The examples expose `architecture` containing network, compute, entrypoint, data and storage_and_logs. They do not forward the root nat output. Conditional nulls are controlled by inputs; required IDs are not silently replaced with null on attribute errors.

## 9. Notes

- Ownership and import: supplying existing IDs does not import or change existing network/data settings. Confirm their region, CIDRs, routing, allow lists, authentication, backups and protection. Domain, certificate, images, key pair and contact groups remain caller-owned. Data endpoints should lie in data subnet ranges or require explicit additional egress.
- Replacement: zone keys, tier keys and instance indexes determine addresses. Renaming keys, switching creation/reuse or ECS/ASG can destroy/recreate resources. Review actual replacement plans for VPC/subnet/zone/image/specification changes. Real cloud updates and replacements remain unverified.
- ASG: backend `servers` is null when ASG owns registration; do not simultaneously manage static members. Optional+Computed readback needs real no-change verification. ASG members do not inherit independent ECS-resource deletion protection.
- CLB: Provider 0.0.73 exposes log enabled/tls_enabled as computed-only. Binding a log destination does not prove logging is enabled; verify readback and record any console action. CLB has no ALB-equivalent deletion protection. Supply official regional health-check CIDRs.
- Data and backups: no MySQL/Redis public-address resource is created. MySQL daily backup uses 18:00Z–19:00Z UTC; production Redis uses UTC+8 backup hours. Standalone Redis has no backup support. TOS versioning does not provide cross-region replication, KMS or object lock.
- State and tags: sensitive values remain in State/Plan. Use a verified encrypted, locked, access-controlled backend. Supported resources receive common tags; allow-list schemas have no tags field. Never commit credentials, real tfvars, State or Plan.
- Destroy maintenance: preserve required data and empty all bucket versions. Keep the prod topology and use deletion_protection=false and allow_protection_disable=true for maintenance and destroy. Review the plan first: Provider 0.0.73 plans ALB protection disabling as replacement, so do not directly apply a full plan that replaces a protected ALB. The retest targeted only existing ECS/MySQL/Redis and their security-group dependencies: zero creations, six in-place updates, zero deletions, and a successful apply. This cleanup maintenance does not establish overall deployment success. Disable deletion protection for the exact ALB in its console, or call the official ModifyLoadBalancerAttributes with its precise LoadBalancerId and DeletionProtection=off. Independently verify ALB/MySQL/Redis protection is disabled. Then run ordinary destroy. If the Redis allow list returns AllowListBindInstanceCannotDelete, query instance deletion and current allow-list bindings first. If TOS is confirmed NotFound but its asynchronous deletion task remains stalled, stop the current Terraform command and preserve its result. After that command ends, rerun the same destroy so the provider refreshes actual state; never launch concurrent destroys. The retest retry exited 0, emptied State, and independently confirmed all 41 known explicit/implicit objects absent. Do not replace deletion verification with state rm. If final MySQL backups need not be retained, call ModifyBackupPolicy for the exact instance with DataKeepPolicyAfterReleased=None and verify zero backups. Redis final backups require seven-day retention and expiry recheck; three known backups currently remain.
- Engineering: the repository follows the VPC module layout: reusable root, basic/complete examples, bilingual README files, outputs.tf, LICENSE, SECURITY.md, CHANGELOG.md and a Terraform formatting hook. Domain-specific .tf files share the root lifecycle. Run `terraform fmt -check -recursive` or `tofu fmt -check -recursive` with the engines in Requirements. Local acceptance reports, test fixtures, credentials and caches are excluded from version control. Static checks do not prove real update/remove/replace behavior.

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
