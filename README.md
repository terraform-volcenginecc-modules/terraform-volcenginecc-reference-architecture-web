# terraform-volcenginecc-reference-architecture-web

A Volcengine module for three-tier Web infrastructure, covering networking, compute, ingress, data, storage and logs.

Module source: `terraform-volcenginecc-modules/reference-architecture-web/volcenginecc`; module version: `version = "~> 1.0"` (>= 1.0.0, < 2.0.0). Provider version requirements are separate. Registry installation requires a published module release in this range.

## 1. Overview

Build single-zone development or multi-zone production infrastructure with edge, web, app and data subnets: load balancer → Web → App → private MySQL/Redis, plus TOS, TLS and optional monitoring, Web ASG and NAT. Public ingress uses only the load balancer; ECS has no public EIP, and NAT configures SNAT only for Web/App. Existing network and data IDs remain caller-owned. The caller installs applications and configures DNS, certificates and log collection.

## 2. Usage

Prepare zone IDs, images with Web/App services installed, ECS and MySQL specifications, an existing key pair and a region-unique bucket name. Web should listen on `8080` and serve `/health`; App should listen on `8080`. Use the visitors' actual public egress CIDRs for ingress and actual DNS/TOS/TLS endpoint CIDRs, protocols and ports for service egress. Confirm routes, permissions, service activation and quotas.

This configuration uses the same remote Registry module source as `main.tf` in both examples. Save this complete configuration in a separate caller directory to avoid duplicate variable or provider declarations. It demonstrates a minimal private HTTP ALB invocation. The existing basic example uses a public HTTP CLB and different ingress settings.

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

Inject credentials through the provider-supported `VOLCENGINE_ACCESS_KEY` and `VOLCENGINE_SECRET_KEY`; supply passwords through `TF_VAR_database_password`, `TF_VAR_cache_password` or platform sensitive variables. Use Terraform `1.5.7` in the caller directory with the required `terraform.tfvars` and a separate State/backend. Keep real inputs and passwords out of the README and Git.

```bash
terraform init
terraform plan -out=部署计划.tfplan
terraform apply 部署计划.tfplan
terraform output -json
```

After Apply, use compute and data endpoints to configure the Web proxy, application database and cache connections. Configure TOS access, log collection and any required DNS. Verify ingress, Web → App → MySQL/Redis, isolation and explicit egress, then check idempotency:

```bash
terraform plan
```

Expect `No changes`. Before destruction, remove bucket objects, historical versions and delete markers. If protection is enabled, disable it and verify actual service settings as described in section 9, then run:

```bash
terraform destroy
```

The README and both examples call the remote module through `terraform-volcenginecc-modules/reference-architecture-web/volcenginecc`.

## 3. Examples

- `examples/basic`: single-zone development with four subnets, one Web and one App instance, public HTTP CLB, one NAT, private single-node MySQL/Redis, TOS and TLS. Prepare regional dependencies, both passwords, ingress CIDRs and service egress rules.

- `examples/complete`: two-zone production configuration with eight subnets, two static Web and two App instances, public HTTPS ALB, one shared NAT, cross-zone MySQL/Redis, 90-day TLS retention, 30-day MySQL backups and at least one monitoring rule. Also prepare a certificate, domain, contact groups and ownership tags. Existing network/data resources and CLB are optional; the caller manages existing network routes and NAT.

Both examples disable ASG. With all resources newly created and one monitoring rule in complete, expected managed resource counts are 27 and 37. Reuse and monitoring rule counts change these totals; service-created implicit resources are excluded.

## 4. Requirements

| Name | Version |
|---|---|
| Terraform | Source constraint `>= 1.5.7, < 1.12.0`; fixed project baseline `= 1.5.7` |
| `volcengine/volcenginecc` | Root module `>= 0.0.73`; both examples pin `= 0.0.73` |

The source allows a broader engine range than the fixed baseline. The caller verifies regional specifications, certificates, service permissions and quotas.

## 5. Providers

| Name | Source |
|---|---|
| `volcenginecc` | `volcengine/volcenginecc` |

The root module declares the provider dependency without region, credentials or aliases; the caller supplies configuration. See the [Registry documentation](https://registry.terraform.io/providers/volcengine/volcenginecc/0.0.73/docs).

## 6. Resources

| Mode | Type | Name |
|---|---|---|
| Create | `volcenginecc_vpc_vpc` | `volcenginecc_vpc_vpc.this` |
| Create | `volcenginecc_vpc_subnet` | `volcenginecc_vpc_subnet.this` |
| Create | `volcenginecc_vpc_security_group` | `volcenginecc_vpc_security_group.this` |
| Create | `volcenginecc_ecs_instance` | `volcenginecc_ecs_instance.this` |
| Create | `volcenginecc_ecs_launch_template` | `volcenginecc_ecs_launch_template.web` |
| Create | `volcenginecc_autoscaling_scaling_group` | `volcenginecc_autoscaling_scaling_group.web` |
| Create | `volcenginecc_alb_acl` | `volcenginecc_alb_acl.this` |
| Create | `volcenginecc_alb_load_balancer` | `volcenginecc_alb_load_balancer.this` |
| Create | `volcenginecc_alb_server_group` | `volcenginecc_alb_server_group.this` |
| Create | `volcenginecc_alb_listener` | `volcenginecc_alb_listener.this` |
| Create | `volcenginecc_clb_acl` | `volcenginecc_clb_acl.this` |
| Create | `volcenginecc_clb_clb` | `volcenginecc_clb_clb.this` |
| Create | `volcenginecc_clb_server_group` | `volcenginecc_clb_server_group.this` |
| Create | `volcenginecc_clb_listener` | `volcenginecc_clb_listener.this` |
| Create | `volcenginecc_natgateway_ngw` | `volcenginecc_natgateway_ngw.this` |
| Create | `volcenginecc_vpc_eip` | `volcenginecc_vpc_eip.nat` |
| Create | `volcenginecc_natgateway_snatentry` | `volcenginecc_natgateway_snatentry.this` |
| Create | `volcenginecc_vpc_route_table` | `volcenginecc_vpc_route_table.private` |
| Create | `volcenginecc_rdsmysql_allow_list` | `volcenginecc_rdsmysql_allow_list.this` |
| Create | `volcenginecc_rdsmysql_instance` | `volcenginecc_rdsmysql_instance.this` |
| Create | `volcenginecc_redis_allow_list` | `volcenginecc_redis_allow_list.this` |
| Create | `volcenginecc_redis_instance` | `volcenginecc_redis_instance.this` |
| Create | `volcenginecc_tos_bucket` | `volcenginecc_tos_bucket.this` |
| Create | `volcenginecc_tls_project` | `volcenginecc_tls_project.this` |
| Create | `volcenginecc_tls_topic` | `volcenginecc_tls_topic.this` |
| Create | `volcenginecc_cloudmonitor_rule` | `volcenginecc_cloudmonitor_rule.this` |

These are 26 resource declarations, not a fixed instance count. The root has no data sources or local submodules. Reuse omits VPC/subnet creation or the corresponding data instances and allow lists; ALB and CLB are alternatives. ASG replaces static Web ECS with a launch template and scaling group while App remains static. Logs create one TLS project and application/access/health topics; each monitoring key creates one rule.

## 7. Inputs

| Name | Type | Default | Required in create mode | Description |
|---|---|---|---|---|
| `name` | `string` | None | Yes | Name prefix and Project tag; 3–31 lowercase letters, digits or hyphens, starting with a letter. |
| `environment` | `string` | `"dev"` | No | `dev` or `prod`; production constraints are listed below. |
| `tags` | `map(string)` | `{}` | No | Ownership tags; the module overrides Project/Environment. |
| `vpc_cidr` | `string` | `"10.20.0.0/16"` | No | Valid IPv4 VPC CIDR; match the actual network when reusing. |
| `zones` | `map(object)` | None | Yes | Zones and four subnet CIDRs; complete fields and matching rules are below. |
| `existing_vpc_id` | `string` | `null` | No | A non-null ID reuses a VPC and requires all existing subnets. |
| `existing_subnet_ids` | `map(string)` | `{}` | No | Required for VPC reuse; keys combine logical zone keys with tier suffixes. |
| `web` | `object` | None | Yes | Web image, specification, instance count per zone and system disk. |
| `app` | `object` | None | Yes | App image, specification, instance count per zone and system disk. |
| `key_pair_name` | `string` | None | Yes | Existing ECS key pair name. |
| `web_port` | `number` | `8080` | No | Load balancer → Web port; integer 1–65535. |
| `app_port` | `number` | `8080` | No | Web → App port; integer 1–65535. |
| `load_balancer` | `object` | None | Yes | Ingress type, sources, HTTPS and health checks. |
| `autoscaling` | `object` | `{}` | No | Optional Web ASG capacity; no metric scaling policy is created. |
| `existing_database_id` | `string` | `null` | No | Existing private MySQL; mutually exclusive with `database`. |
| `database` | `object` | `null` | Yes, for new MySQL | MySQL specification, storage, account and backup settings. |
| `database_password` | `string` | `null` | Yes, for new MySQL | Sensitive password, non-null during creation; follow service password rules. |
| `existing_cache_id` | `string` | `null` | No | Existing private Redis; mutually exclusive with `cache`. |
| `cache` | `object` | `null` | Yes, for new Redis | Redis version, capacity and backup time. |
| `cache_password` | `string` | `null` | Yes, for new Redis | Sensitive password, non-null during creation; authentication is enabled. |
| `bucket_name` | `string` | None | Yes | Region-unique, 3–63 lowercase letters, digits or hyphens, with alphanumeric ends. |
| `enable_logs` | `bool` | `true` | No | Create a TLS project and three topics; required in production. |
| `log_retention_days` | `number` | `30` | No | TLS retention, integer 1–3650 days. |
| `deletion_protection` | `bool` | `false` | No | Protect ECS, new RDS/Redis and ALB; enable for normal production. |
| `allow_protection_disable` | `bool` | `false` | No | Allow protection to be disabled during production maintenance; does not destroy resources. |
| `monitoring` | `map(object)` | `{}` | No | Explicit metric rules and contact groups, selecting resources by Project tag. |
| `service_egress` | `map(object)` | `{}` | No | Explicit endpoint egress shared by Web/App; supply what the application needs. |
| `nat` | `object` | `{}` | No | Optional shared VPC egress NAT, EIP and Web/App SNAT. |

Complete object fields follow. Values inside `optional` are field defaults; optional fields without defaults become `null`. Object defaults of `{}` apply their nested field defaults.

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

`zones` requires at least one unique `zone_id`; all subnets must be valid, non-overlapping IPv4 CIDRs inside the VPC. For reuse, `existing_subnet_ids` must exactly match all logical zone keys with `-edge`, `-web`, `-app` and `-data` suffixes; leave the map empty for a new VPC. MySQL/Redis use the first one or two sorted logical zone keys, so keep these keys stable.

`web/app.count_per_zone` is an integer 1–1024, with system disks of at least 40 GiB; specifications and disk types must exist in the target region. `load_balancer.kind` is `alb/clb`; `allowed_cidrs` must be nonempty and valid IPv4 CIDRs. HTTPS requires both a certificate-center ID and domain. Health paths start with `/`, and bandwidth is at least 1 Mbps. CLB requires nonempty `health_check_cidrs`, but the current Web security group source remains fixed at `100.64.0.0/10`; this input does not change its rules.

ASG capacities are integers satisfying `1 <= min <= desired <= max`; production `min` must cover the zone count. New MySQL storage is at least 20 GiB with 7–3650 days of backup retention. Redis capacity is at least 256 MiB; backup hours are integers 0–23, and development single-node Redis has no backup plan. Production creates cross-zone two-node MySQL and Redis and requires at least two zones, HTTPS, logs and protection; only the explicit maintenance flag permits disabling protection.

Each monitoring rule supplies the official metric region, namespace/sub_namespace, name, unit, threshold and nonempty contact groups, with `evaluation_count >= 1`. Service egress uses valid IPv4 CIDRs, `tcp/udp` and integer ports 1–65535; the module creates neither these endpoints nor their permissions. NAT bandwidth is 1–200 Mbps; enabled NAT requires a `zone_key` matching `zones` and creates one gateway per VPC. The caller manages routes in reused VPCs. Both examples require nonempty database/cache passwords even when complete reuses data instances.

## 8. Outputs

| Name | Type | Description |
|---|---|---|
| `network` | `object` | `vpc_id`, `subnet_ids`, `security_group_ids` for private connectivity and references; may include existing resource IDs. |
| `compute` | `object` | `instances` maps stable keys to static ECS `id` and `network_interface`; `scaling_group_id` is non-null only with ASG, whose members are service-managed. |
| `entrypoint` | `object` | Ingress `id`, `server_group_id`, `domain`, `alb_dns_name`, `clb_public_ip`; only the selected type's address is populated, and domain can be null. |
| `data` | `object` | `database_id`, `cache_id`, `mysql_endpoints`, `redis_private_address`; endpoints are null on reuse and must be queried by the caller. |
| `storage_and_logs` | `object` | `bucket_name`, `tls_project_id`, `topic_ids`, `monitoring_rule_ids`; disabled logs yield a null project ID and empty topic map, and absent monitoring yields an empty rule map. |
| `nat` | `object` | `gateway_ids`, `eip_ids`, `snat_ids`, `route_table_ids`; all are empty when NAT is disabled, and zone keys share the same gateway/EIP. |

IDs, addresses and domains are strings, and resource collections are maps. `network_interface` and `mysql_endpoints` retain the provider's nested structures. Use ingress values for DNS, private compute/data endpoints for applications and storage/log IDs for access and collection. Both examples expose only the first five groups through `architecture`, without forwarding `nat`.

## 9. Notes

Existing resources are referenced by ID without import. The module does not change their accounts, allow lists, backups, protection or network routes, and does not destroy them. Changes to names, zone keys, images, subnets or specifications may update or replace resources; review the Plan.

Ingress ACLs allow client sources. Web ingress allows only `100.64.0.0/10` to `web_port`; Web → App uses `app_port`, and App → data uses 3306/6379 with application subnet allow lists. Business and explicit endpoint allow rules use priority 1, fallback denial uses 99 and platform-added default allow rules use 100, so the latter cannot bypass denial. There is no default SSH ingress or unrestricted egress; NAT does not grant security group access.

Enabled NAT creates SNAT and separate route tables only for Web/App. Data subnets retain the system route table, where the NAT service may automatically add `0.0.0.0/0 → NAT`. The current code does not bind data to an isolated route table, so an absent public default route cannot be claimed. Data has no SNAT; tested paths showed no public data exposure, but active data-subnet internet egress has not been directly tested.

ALB can send access logs to TLS; creating topics does not install application log collection. This module does not configure CLB access logs or CLB deletion protection. HTTP CLB health checks omit the port override and follow the Web backend `8080`; the business port remains configured. Provider `0.0.73` has ASG launch-template readback defects; both examples disable ASG, whose path has not passed acceptance.

Before deleting protected resources, set `deletion_protection=false`; production also requires `allow_protection_disable=true`. Review the update Plan and verify actual ECS/RDS/Redis/ALB protection. An ALB protection update may plan replacement: first disable `DeleteProtection` for that ALB through its native service, then review the Plan before proceeding. Remove all TOS versions. RDS final backups may remain, and Redis final backups are retained for seven days. Sensitive passwords still enter State; the caller protects State and credentials.

Isolated copies of the same implementation previously completed one Apply from empty State for basic/complete and business checks after application initialization. Each second `terraform plan` still contains four RDS/TOS/security-group drifts and has not reached `No changes`. Standard Destroy failed on asynchronous TOS/CLB tasks and Redis allow-list unbinding; later cleanup retries do not establish a successful full lifecycle. Production platform tests also showed disabled deletion protection and an empty TOS version status; verify native service settings before production use.
