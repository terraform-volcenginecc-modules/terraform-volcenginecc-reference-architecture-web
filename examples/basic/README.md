# BASIC Web architecture Example

## 1. Overview

Create a single-zone development environment with four subnet tiers, public HTTP CLB, one Web and one App instance, private single-node MySQL/Redis, one egress NAT, TOS and TLS. Unlike complete, it omits two-zone deployment, HTTPS, monitoring and production deletion protection. Prepare zones, service images, specifications, a key pair, a bucket name, both passwords, ingress sources and service egress rules. The caller configures application connections and log collection.

## 2. Usage

Run from `examples/basic` in an isolated full repository copy. The current `main.tf` uses a Registry source that requires publication; publication status and module versions were not verified in this update. For local testing before publication, change only the copied `module.web.source` to `../..`, keeping the original repository guidance. Local sources have no `version`.

Use Terraform `1.5.7` and supply this directory's required `terraform.tfvars` inputs and both sensitive passwords. Images must provide Web `8080`, `/health` and App `8080`. Confirm service activation, available regional specifications, private endpoint routes and permissions. Full creation needs at least two public EIP quota slots for CLB and NAT. Use the actual request egress CIDRs for the ingress allow list.

```bash
terraform init
terraform plan -out=部署计划.tfplan
terraform apply 部署计划.tfplan
terraform output -json architecture
```

Use outputs to configure the Web proxy, App MySQL/Redis connections, TOS access and log agents. Verify public HTTP, Web → App → MySQL/Redis, Web-to-data isolation and explicit NAT egress, then run:

```bash
terraform plan
```

Expect `No changes`; current drift is described in section 9. After testing, review the deletion scope and remove all bucket objects and versions. If protection was separately enabled, disable and apply that update first, then run:

```bash
terraform destroy
```

Keep State, lock files, caches, plans and logs in the isolated copy rather than the source deliverable.

## 3. Requirements

| Name | Version |
|---|---|
| Terraform | `>= 1.5.7, < 1.12.0`; fixed project baseline `= 1.5.7` |
| `volcengine/volcenginecc` | `= 0.0.73` |

These are the actual constraints in this directory's `versions.tf`. The allowed range is broader than the fixed baseline; this update does not change version files.

## 4. Providers

| Name | Source |
|---|---|
| `volcenginecc` | `volcengine/volcenginecc` |

This directory configures the region and optional Cloud Control endpoint without aliases; credentials come from the runtime environment.

## 5. Resources

| Name | Description |
|---|---|
| `module.web` | Actual source `terraform-volcenginecc-modules/reference-architecture-web/volcenginecc`, invoking the three-tier Web root module; local testing in an isolated copy uses `../..`. |

This directory declares no direct resources or data sources. Full creation expects 27 module-managed resources, including one Web, one App, four subnets, two SNAT entries and one Web/App route table. ASG is disabled; service-created implicit resources are excluded.

## 6. Inputs

| Name | Description |
|---|---|
| `deployment` | Required object: `name`, `region`, `zone_id`, `web_image_id`, `app_image_id`, `web_instance_type`, `app_instance_type`, `key_pair_name`, `database_node_spec`, `bucket_name` are strings; `allowed_cidrs` is a nonempty `set(string)`. Supply verified regional dependencies and ingress sources. |
| `database_password` | Required sensitive string, neither null nor blank; inject through `TF_VAR_database_password` or platform sensitive variables and follow MySQL password rules. |
| `cache_password` | Required sensitive string, neither null nor blank; inject through `TF_VAR_cache_password` or platform sensitive variables and follow Redis password rules. |
| `service_egress` | Required `map(object({cidr=string, protocol=string, port=number}))`; use actual DNS/TOS/TLS endpoint rules with valid CIDRs, tcp/udp, integer ports 1–65535 and working routes. |
| `tags` | Optional `map(string)`, default `{}`; supply Owner/CostCenter tags. The module sets Project/Environment. |
| `cloudcontrol_endpoint` | Optional string, default `null` for the provider default; configure a Cloud Control API address only for an explicit environment requirement. |

VPC CIDR is fixed at `10.20.0.0/16`; primary edge/web/app/data use `10.20.0.0/24` through `10.20.3.0/24`. This example exposes no existing-resource reuse inputs. Web/App each use one instance per zone and 40 GiB ESSD_PL0 system disks. MySQL defaults to 100 GiB and seven-day backups; development Redis is single-node with no backup plan. CLB and NAT each default to 10 Mbps, and TLS retention is 30 days.

## 7. Outputs

| Name | Description |
|---|---|
| `architecture` | Object containing `network`, `compute`, `entrypoint`, `data`, `storage_and_logs`; use private interfaces/data endpoints for applications, the CLB public address for ingress and Bucket/TLS IDs for storage and collection. The root `nat` output is not forwarded. |

## 8. Example

This directory is the basic example for single-zone development and minimal three-tier checks. Use complete for two zones, HTTPS, cross-zone data instances and monitoring, supplying its additional inputs.

## 9. Notes

Inject credentials using provider-supported runtime settings such as `VOLCENGINE_ACCESS_KEY` and `VOLCENGINE_SECRET_KEY`, and passwords using sensitive variables. State still contains sensitive values and must be protected by the caller. The caller supplies application installation, connections, log agents and private maintenance access; there is no default SSH ingress.

The HTTP CLB listener reaches Web on backend port `8080`, and health checks omit the port override to follow the backend. Web security group sources remain fixed at `100.64.0.0/10`. Service egress allows only explicit rules; priority 99 denial takes precedence over platform priority 100 default allow rules. A single ingress CIDR permits only that egress source; maintain the list when networks or users change.

NAT creates SNAT only for Web/App. Data retains the system route table, which may contain the NAT service's automatically added default route; no isolated data route table is bound. Data has no SNAT, so a default route alone does not prove public connectivity. Active data-subnet egress has not been directly tested.

An isolated copy of the same implementation previously completed one Apply from empty State and business checks after application initialization; current Registry installation is unverified. The post-Apply `terraform plan` must show no changes for idempotency, but existing results still have four RDS/TOS/security-group drifts. Standard Destroy failed on asynchronous TOS and CLB deletion tasks; subsequent cleanup retries do not establish a successful full lifecycle. RDS/Redis final backups may remain under service policy, with Redis retained for seven days. This documentation check does not constitute renewed acceptance.
