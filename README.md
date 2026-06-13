# Wazuh Auto-Scaling Fleet

Terraform deployment of a horizontally-scaled Wazuh agent fleet behind an
Application Load Balancer, plus a small policy-as-code toolkit for checking
and auto-remediating specific Terraform security settings.

## Architecture

```
Internet
   |
   v
[ALB] --443 (TLS)--> [Target Group :80]
   |  HTTP:80 redirects to HTTPS:443
   v
[ASG, 1-4 instances across 2 private subnets]
   each instance runs:
     - "my-app" container (nginx placeholder for the actual workload)
     - "wazuh-agent" container (FIM + log monitoring, registers with
       the Wazuh manager using a KMS-decrypted password)
```

- **ALB**: public-facing, TLS-terminated (`ELBSecurityPolicy-TLS13-1-2-2021-06`),
  HTTP→HTTPS redirect.
- **ASG**: 1-4 `t2.micro` instances across two private subnets, behind the ALB.
- **Security groups**: ALB↔App traffic on 80, agent enrollment (1514/1515) and
  Wazuh API (55000) between app instances, egress restricted to a specific
  proxy/NAT endpoint on 443 — no broad `0.0.0.0/0` egress from the app tier.
- **IMDSv2 enforced** on the launch template (`http_tokens = "required"`,
  hop limit 1).
- **Secrets**: the Wazuh agent registration password is passed as a
  KMS-encrypted ciphertext blob and decrypted at boot via an IAM role with
  scoped `kms:Decrypt` permission.

## Required Variables

None of the variables below have defaults — they're all account/environment
specific. Copy `terraform/terraform.tfvars.example` to
`terraform/terraform.tfvars` (gitignored) and fill in real values.

| Variable | Description |
|---|---|
| `vpc_id` | VPC ID for all resources |
| `alb_subnet_1`, `alb_subnet_2` | Public subnets for the ALB (different AZs) |
| `private_subnet_1`, `private_subnet_2` | Private subnets for the ASG (different AZs) |
| `ami_id` | AMI for the launch template |
| `my_acm_certificate_arn` | ACM cert ARN for the ALB's HTTPS listener |
| `kms_key_arn` | KMS key ARN the instance role can use for `kms:Decrypt` |
| `proxy_ip` | CIDR of the outbound proxy/NAT endpoint (e.g. `10.0.0.5/32`) |
| `wazuh_manager_ip` | Private IP/DNS of the Wazuh manager agents register with |
| `encrypted_wazuh_pass` | KMS-encrypted, base64 Wazuh registration password |

To generate `encrypted_wazuh_pass`:

```bash
aws kms encrypt --key-id <kms_key_arn> \
  --plaintext "your-wazuh-registration-password" \
  --query CiphertextBlob --output text
```

## Deploying

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # then edit with real values
terraform init
terraform plan
terraform apply
```

## Policy-as-Code: `settings_checker.py`

Checks specific `.tf` files for security settings and can auto-fix them.

```bash
# Report only, no changes
python3 settings_checker.py -f terraform/alb.tf terraform/ec2.tf terraform/sg.tf --dry-run

# Apply fixes in place
python3 settings_checker.py -f terraform/alb.tf terraform/ec2.tf terraform/sg.tf
```

Checks implemented:

| File | Check |
|---|---|
| `alb.tf` | `drop_invalid_header_fields` is present and `true` |
| `ec2.tf` | Launch template `metadata_options` enforces IMDSv2 (`http_tokens = "required"`, hop limit `1`) |
| `sg.tf` | No egress rule has `cidr_ipv4 = "0.0.0.0/0"` |

Output is written to `report.json` (gitignored). Files outside this list log
"No checks implemented" and are recorded as such in the report.

> **Note:** the `sg.tf` check looks specifically for a literal
> `cidr_ipv4 = "0.0.0.0/0"` egress rule. The current `sg.tf` restricts egress
> via `var.proxy_ip` instead, so the check correctly reports no issue — but
> logs "No app egress rule found", which is misleading wording (an app
> egress rule does exist; it's just not the pattern being searched for).

## IaC Scanning: `trivy_automatic_scan.sh`

Runs [Trivy](https://github.com/aquasecurity/trivy) against every file in
`terraform/`, failing on HIGH/CRITICAL findings.

```bash
./trivy_automatic_scan.sh
```

Requires `trivy` installed and on `PATH`. Per-file reports
(`trivy_scan_<file>.txt`) are written only for files with findings and are
gitignored.

### Accepted findings (`trivy:ignore` annotations)

- **`alb.tf` — AVD-AWS-0107** (ALB allows public ingress on 80/443): intentional,
  this is a public-facing ALB. In production this would sit behind AWS WAF.
- **`alb.tf` — AVD-AWS-0053** (ALB deletion protection disabled): intentional
  for a lab/demo environment — `enable_deletion_protection` should be `true`
  in production.

## Known Limitations

- The Wazuh agent container runs with `--cap-add=SYS_ADMIN`,
  `--cap-add=SYS_PTRACE`, `--cap-add=NET_ADMIN` and mounts `/`, `/etc`,
  `/var/log`, `/dev`, and the Docker socket — necessary for File Integrity
  Monitoring and container visibility, but worth knowing this is a
  high-privilege container even without `--privileged`.
- `my-app` (nginx) is a placeholder for whatever workload this fleet is
  actually monitoring.
- No CI workflow yet — `trivy_automatic_scan.sh` and `settings_checker.py`
  are run manually.
