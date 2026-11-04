# Basic Web architecture

A single-zone development example with a public HTTP CLB, private Web/application ECS, private single-node MySQL/Redis, outbound NAT, private TOS and TLS logs.

It plans 27 managed resources across four subnets in 10.20.0.0/16: edge 10.20.0.0/24, web 10.20.1.0/24, app 10.20.2.0/24 and data 10.20.3.0/24. One Web ECS and one application ECS have no public EIP. Web/application use SNAT; the data subnet has no module-managed public default route. Listener ACL limits clients; Web/app security groups and data allow lists constrain inter-tier traffic. The official CLB service range is 100.64.0.0/10. HTTP and single-zone data are development choices. MySQL has daily backups; standalone Redis has no backup support.

The calling example manages the Provider and uses `source = "terraform-volcenginecc-modules/reference-architecture-web/volcenginecc"`. The module is unpublished; Registry installation is unverified, and no release version is invented. Static validation redirects the source only in temporary copies. Engine constraint is >= 1.5.7, < 1.12.0; exact validation targets are Terraform 1.5.7 and OpenTofu 1.11.8 with Registry Provider 0.0.73.

Prepare verified region/zone, preinstalled Web/application images serving port 8080 and /health, available ECS/RDS specifications, an existing key pair, enabled services, permissions and quotas. Supply actual private DNS/TOS/TLS endpoint CIDRs and routing through service_egress; NAT alone does not grant endpoint access. Configure application proxy/data connections and log agents yourself.

| Input | Type | Default / requirement |
|---|---|---|
| `deployment` | object | Required; fields below |
| `database_password` | string, sensitive | Required through TF_VAR_database_password |
| `cache_password` | string, sensitive | Required through TF_VAR_cache_password |
| `service_egress` | map(object({cidr=string, protocol=string, port=number})) | Required; actual IPv4 CIDR, tcp/udp, integer 1–65535 |
| `tags` | map(string) | {}; Project/Environment set by module |
| `cloudcontrol_endpoint` | string | null; default online API endpoint |

| Deployment field | Type | Requirement |
|---|---|---|
| `deployment.name` | string | Required stable name, 3–31 lowercase letters/digits/hyphens, starts with a letter |
| `deployment.region` | string | Required verified region |
| `deployment.zone_id` | string | Required available zone |
| `deployment.web_image_id` | string | Required preinstalled Web image |
| `deployment.app_image_id` | string | Required preinstalled application image |
| `deployment.web_instance_type` | string | Required available Web specification |
| `deployment.app_instance_type` | string | Required available application specification |
| `deployment.key_pair_name` | string | Required existing key pair |
| `deployment.database_node_spec` | string | Required available MySQL specification |
| `deployment.bucket_name` | string | Required region-unique bucket name |
| `deployment.allowed_cidrs` | set(string) | Required nonempty explicit client IPv4 CIDRs |

Put actual deployment/service_egress/tags values in a private deployment.tfvars. Use VOLCENGINE_ACCESS_KEY and VOLCENGINE_SECRET_KEY unchanged; keep credentials and real input files outside Git. After publication, run from examples/basic using one engine and its own State:

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

The architecture object contains network, compute, entrypoint, data and storage_and_logs from the root module; it does not forward nat. Use the CLB public IP for access, private interface/data addresses for application configuration, and storage/log IDs for service integration. ASG ID, domain and ALB DNS are null in this configuration; monitoring IDs are empty. No passwords are output. Verify entry access and ACL denial, Web-to-app and app-to-MySQL/Redis connectivity, TOS permissions, TLS logs and a second plan reporting No changes.

Preserve required data, empty the bucket and all versions, then destroy and query both managed and service-created resources/backups to confirm removal. Empty State is insufficient.

```bash
terraform destroy -var-file=deployment.tfvars
```

```bash
tofu destroy -var-file=deployment.tfvars
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

Final retest: basic planned 27 resources, created 23 State objects, and stopped on image/type mismatch. Native destroy retry exited 0; all 30 known objects were absent and final MySQL/Redis backup counts were zero after MySQL compensation.

Local acceptance evidence is retained separately. Registry module consumption and OpenTofu cloud lifecycle remain unverified.
