# COMPLETE Web architecture Example

## 1. Overview

Configure two-zone production infrastructure with eight subnets, two static Web and two App instances, public HTTPS ALB, cross-zone MySQL/Redis, one shared NAT, TOS, 90-day TLS and explicit monitoring. Compared with basic, it adds certificates, a domain, cross-zone data, backups and protection settings, and supports existing network/data IDs. Prepare regional dependencies, both passwords, ingress sources, endpoint egress, contact groups and ownership tags; configure applications and logs.

## 2. Usage

Run from `examples/complete` in an isolated full repository copy. `main.tf` calls the remote three-tier Web module through `terraform-volcenginecc-modules/reference-architecture-web/volcenginecc`.

Use Terraform `1.5.7` and supply the required `terraform.tfvars` inputs, both sensitive passwords, specifications for both zones and images with Web/App installed. Web must provide `8080` and `/health`; App must provide `8080`. Match the HTTPS certificate to the domain and supply at least one verified official metric rule and contact group. Confirm services, private endpoint routes and permissions. Default full creation needs at least three public EIP quota slots for two-zone ALB and NAT.

Keep `deletion_protection=true` and `allow_protection_disable=false` for normal deployment. For reuse, supply all eight subnet IDs and match their CIDRs to this example. The caller maintains authentication, App subnet allow lists, backups and protection for existing MySQL/Redis.

```bash
terraform init
terraform plan -out=部署计划.tfplan
terraform apply 部署计划.tfplan
terraform output -json architecture
```

Configure DNS, the Web proxy, private App MySQL/Redis connections, TOS access and log collection using outputs. Verify HTTPS, Web → App → data across both zones, isolation, shared NAT, logs and alerts, then run:

```bash
terraform plan
```

Expect `No changes`; current drift is described in section 9. Before deletion, remove all TOS objects, versions and delete markers. In a confirmed maintenance window, set both `deletion_protection=false` and `allow_protection_disable=true`:

```bash
terraform plan -out=关闭保护计划.tfplan
```

Review the intended scope. If the ALB protection update plans replacement, first disable `DeleteProtection` for the specific ALB through its native service. Re-plan and review before applying protection updates for other resources:

```bash
terraform plan -out=关闭保护计划.tfplan
terraform apply 关闭保护计划.tfplan
```

Verify actual ECS/RDS/Redis/ALB protection is disabled and existing resources are excluded from deletion, then run:

```bash
terraform destroy
```

Keep State, lock files, caches, plans and logs in the isolated copy or a separate backend.

## 3. Requirements

| Name | Version |
|---|---|
| Terraform | `>= 1.5.7, < 1.12.0`; fixed project baseline `= 1.5.7` |
| `volcengine/volcenginecc` | `= 0.0.73` |

These are the actual constraints in this directory's `versions.tf`. The allowed range is broader than the fixed baseline.

## 4. Providers

| Name | Source |
|---|---|
| `volcenginecc` | `volcengine/volcenginecc` |

This directory configures the region and optional Cloud Control endpoint without aliases; authentication comes from the runtime environment.

## 5. Resources

| Name | Description |
|---|---|
| `module.web` | Source `terraform-volcenginecc-modules/reference-architecture-web/volcenginecc`, invoking the remote three-tier Web module. |

This directory declares no direct resources or data sources. Default ALB with all resources newly created and one monitoring rule expects 37 module-managed resources, including eight subnets, four static ECS instances, one NAT, four SNAT entries and two Web/App route tables. ASG is disabled. Reuse and additional monitoring rules change the total; implicit resources are excluded.

## 6. Inputs

| Name | Description |
|---|---|
| `deployment` | Required object: `name`, `region`, `zone_a`, `zone_b`, `web_image_id`, `app_image_id`, `web_instance_type`, `app_instance_type`, `key_pair_name`, `database_node_spec`, `bucket_name`, `domain`, `certificate_id` are strings; `allowed_cidrs` is a nonempty `set(string)`. Use distinct zones, a matching certificate/domain and actual request egress sources. |
| `existing` | Optional object, default `{}`; optional strings `vpc_id`, `database_id`, `cache_id` default to null; optional `subnet_ids` is `map(string)` defaulting to `{}`. VPC reuse requires all eight subnets, disables module NAT and leaves routes to the caller. |
| `database_password` | Required sensitive string, neither null nor blank, supplied through `TF_VAR_database_password` or platform sensitive variables. Still required when reusing MySQL; the module does not update existing passwords. |
| `cache_password` | Required sensitive string, neither null nor blank, supplied through `TF_VAR_cache_password` or platform sensitive variables. Still required when reusing Redis; the module does not update existing passwords. |
| `service_egress` | Required `map(object({cidr=string, protocol=string, port=number}))`; actual endpoint CIDRs, tcp/udp, integer ports 1–65535 and corresponding routes. |
| `monitoring` | Required nonempty `map(object)` with at least one official metric rule and configured contact group; complete fields are below. |
| `tags` | Required `map(string)` for ownership and costs; the module sets Project/Environment. |
| `load_balancer_kind` | Optional string, default `"alb"`, accepting alb/clb; both use HTTPS. CLB logs/protection limitations are in section 9. |
| `clb_health_check_cidrs` | Optional `set(string)`, default `[]`; CLB requires verified IPv4 sources. The current Web security group still uses fixed `100.64.0.0/10`. |
| `deletion_protection` | Optional bool, default `true`; keep enabled in normal production. Disabling during maintenance also requires the next flag. |
| `allow_protection_disable` | Optional bool, default `false`; true only in a maintenance window to allow disabling protection. Does not destroy resources. |
| `cloudcontrol_endpoint` | Optional string, default `null` for the provider default; configure a Cloud Control API address for explicit environment requirements. |

The complete monitoring type follows. Contact groups must be nonempty and `evaluation_count >= 1`. Verify namespace/sub_namespace, metric name, unit, region and threshold against the official catalog. Rules select resources by the module's Project tag.

```hcl
map(object({
  region = string, namespace = string, sub_namespace = string
  metric_name = string, metric_unit = string, threshold = string
  contact_group_ids = set(string), statistics = optional(string, "avg")
  comparison_operator = optional(string, ">"), evaluation_count = optional(number, 3)
}))
```

VPC CIDR is `10.20.0.0/16`. Primary edge/web/app/data use `10.20.0.0/24` through `10.20.3.0/24`; secondary uses `10.20.4.0/24` through `10.20.7.0/24`. Existing subnet keys combine `primary` or `secondary` with `-edge`, `-web`, `-app` and `-data`. Use the root module directly for other CIDRs.

Each zone has one Web and one App with default 40 GiB ESSD_PL0 system disks. New MySQL uses cross-zone two-node deployment, 100 GiB storage and 30-day backups; new Redis uses two cross-zone nodes and daily backups. TLS retains 90 days, and TOS configures versioning. The module protection input is `deletion_protection || !allow_protection_disable`, so disabling requires false/true together; actual service state still needs verification.

## 7. Outputs

| Name | Description |
|---|---|
| `architecture` | Object containing `network`, `compute`, `entrypoint`, `data`, `storage_and_logs`; use ingress values for DNS, private interfaces/data endpoints for applications and Bucket/TLS/monitoring IDs for storage, collection and alerts. `nat` is not forwarded. |

When reusing MySQL/Redis, `data` retains IDs but returns null endpoints; query existing services separately.

## 8. Example

This directory is the complete example for two-zone HTTPS and production configuration checks, or data reuse in a matching network. Compared with basic, it requires certificates, a domain, monitoring and protection maintenance steps. Verify native service settings before production use.

## 9. Notes

Inject credentials into the runtime through provider-supported settings such as `VOLCENGINE_ACCESS_KEY` and `VOLCENGINE_SECRET_KEY`; use sensitive variables for both passwords. State still contains sensitive values and remains caller-managed. The caller maintains applications, DNS, certificates and log agents; TLS topic creation does not automatically collect application logs.

Existing resources are referenced by ID without import or changes to accounts, allow lists, backups or protection, and are excluded from module Destroy. New networks configure SNAT only for Web/App. Data retains the system route table, which may contain a NAT default route; data has no SNAT and isolated routing is not implemented. Module NAT is disabled for reused networks, whose egress and isolation remain caller-managed.

Static ECS in both zones avoids Provider `0.0.73` ASG launch-template readback defects; ASG has not passed acceptance. CLB does not configure access logs or its own deletion protection. HTTPS certificates and Web business ports must match the services. Security groups allow only business and explicit service traffic; priority 99 denial takes precedence over platform priority 100 allow rules.

An isolated copy of the same implementation previously completed one Apply from empty State and initialized two-zone business checks. The post-Apply `terraform plan` must show no changes for idempotency, but existing results still have four RDS/TOS/security-group drifts. Production platform tests showed disabled actual deletion protection and an empty TOS version status, so configured settings do not establish effective service state.

Standard Destroy failed on asynchronous TOS deletion and Redis allow-list unbinding; later cleanup retries do not establish a successful full lifecycle. Disabling ALB protection may plan replacement; review and disable native protection as described in section 2. Remove all TOS versions before deletion. RDS/Redis final backups may remain, with Redis retained for seven days.
