# Changelog

## Unreleased

- Fix NAT/EIP lookup for zone keys ending in -app or -web by removing only the final subnet tier suffix.
- Limit Web/application count_per_zone to integers from 1 to 1024, matching Terraform range limits.

- Add a layered Web architecture with VPC/subnets, restricted security groups, outbound NAT, ECS/ASG, ALB/CLB, private MySQL/Redis, TOS, TLS and optional monitoring.
- Add basic and complete examples with bilingual documentation and explicit caller-owned dependencies.
- Document verified security-group maintenance and cleanup procedures, plus remaining Provider 0.0.73 limitations.
- Follow the VPC repository layout with outputs.tf, SECURITY.md and a Terraform formatting hook; exclude local validation artifacts.
- Static validation covers Terraform 1.5.7 and OpenTofu 1.11.8. Full cloud acceptance and Registry module consumption remain incomplete.
