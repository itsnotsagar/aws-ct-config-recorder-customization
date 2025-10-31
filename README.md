# AWS Control Tower Config Recorder Customization (Terraform)

> Tip: To force a full re-run across all Control Tower managed accounts, bump `lambda_version` in `variables.tf` (e.g., "1" → "2") and run `terraform apply`. This updates the Producer Lambda config and re-processes all accounts via EventBridge/CloudTrail.

This Terraform solution customizes AWS Config Recorder settings across all AWS Control Tower managed accounts using an event-driven, serverless pattern. It applies region-aware defaults, records critical resources continuously, excludes noisy types, and uses daily recording where appropriate to reduce cost while maintaining useful visibility.

## What it does

- Listens to Control Tower lifecycle events (CreateManagedAccount, UpdateManagedAccount, UpdateLandingZone)
- Fans out account/region work items via SQS
- Assumes `AWSControlTowerExecution` role in target accounts and updates their Config Recorder
- Uses region-specific mappings from `locals.tf` for continuous recording and exclusions

## Architecture (at a glance)

- Event sources: EventBridge rules for Control Tower and Lambda update events
- Orchestrator: Producer Lambda (`ct-config-recorder-producer`)
- Queue: SQS (`ct-config-recorder-queue`)
- Worker: Consumer Lambda (`ct-config-recorder-consumer`)

Key runtime settings (as defined in Terraform):
- Producer: python3.12, memory 512 MB, timeout 900s, reserved concurrency 1
- Consumer: python3.12, memory 512 MB, timeout 900s, reserved concurrency 50
- SQS: visibility timeout 900s, delay 5s, KMS alias `alias/aws/sqs`

## Prerequisites

- AWS Control Tower is set up and managing your accounts
- Permissions to deploy in the Control Tower management account
- Terraform 1.x and AWS provider >= 5.84.0
- AWS credentials for the management account (SSO or access keys). The Consumer assumes `AWSControlTowerExecution` in target accounts.

Backend note: `providers.tf` configures an S3 backend. Update `bucket`, `key`, and `region` for your environment before running Terraform. If you prefer local state, switch the backend accordingly.

## Inputs (variables.tf)

- `excluded_accounts` (list(string), default placeholders): Account IDs to skip (typically management, audit, log archive). Must be 12-digit strings.
- `lambda_log_level` (string, default `INFO`): One of `DEBUG|INFO|WARNING|ERROR`.
- `config_recorder_strategy` (string, default `EXCLUSION`): Currently only `EXCLUSION` is supported.
- `config_recorder_default_recording_frequency` (string, default `DAILY`): Currently only `DAILY`.
- `aws_region` (string, default `eu-west-1`): Deployment and target region for providers.
- `account_id` (string): Account to assume with the provider alias `target` (defaults to a placeholder). Provider assumes role `AWSAFTExecution` with an external ID.
- `lambda_version` (string, default `1`): Increment to force a manual re-run.

Region mappings (locals.tf):
- `region_continuous_resources`: resource types that should be `CONTINUOUS`
- `region_exclusions`: resource types to exclude entirely

These are exported to the Consumer Lambda via env vars `REGION_RESOURCE_TYPES_MAPPING` and `REGION_EXCLUSIONS_MAPPING`.

## Deploy

1) Configure backend and providers
- Edit `providers.tf` backend `bucket`, `key`, `region`
- Adjust `aws_region`/`account_id` in `variables.tf` or via `-var`/
  tfvars

2) Initialize and apply
```bash
terraform init
terraform plan
terraform apply
```

3) First run behavior
- An `aws_lambda_invocation` resource triggers the Producer once after deploy to enqueue work for all accounts.

## Manual triggers

- Bump `lambda_version` in `variables.tf` and `terraform apply` (recommended)
- Update the Producer Lambda configuration in any way that results in a config update event
- Directly invoke the Producer for ad-hoc tests (optional)

## Monitoring

- Logs: `/aws/lambda/ct-config-recorder-producer`, `/aws/lambda/ct-config-recorder-consumer` (retention 90 days)
- Look for Producer messages like "Message sent to SQS" and for Consumer messages referencing `put_configuration_recorder`

## Troubleshooting

- Producer isn’t firing: Verify EventBridge rules exist and CloudTrail is enabled in the management account
- Messages aren’t processed: Check SQS metrics and Consumer Lambda concurrency; verify excluded accounts list
- AssumeRole failures: Ensure `AWSControlTowerExecution` exists and the management account has permission to assume it
- Not seeing updates: Confirm your target region is in `locals.tf` mappings, and verify the resource lists

Enable more logs by setting `lambda_log_level = "DEBUG"` and re-applying.

## Security and cost considerations

- IAM: Minimal policies for Lambda + SQS; Consumer allows `sts:AssumeRole` and expects `AWSControlTowerExecution` in each account
- SQS: Encrypted with AWS-managed KMS key
- Strategy: `EXCLUSION_BY_RESOURCE_TYPES` with `DAILY` default and regional `CONTINUOUS` overrides for critical types

Note: Cost impact depends on your footprint and change rates. This module focuses on reducing noise and avoiding duplicate global resource recording across regions.

## Customize behavior

Edit `locals.tf` to adjust per-region lists:
- Add resource types to `region_continuous_resources` to record them continuously
- Add resource types to `region_exclusions` to exclude them entirely

Changes are picked up by the Consumer via environment variables on the next deploy.

## CI/CD (optional)

The included `.gitlab-ci.yml` provides simple plan/apply stages. Ensure a suitable runner (`tags: [aws-org]`) and AWS credentials are available to the runner, and that your backend is reachable.

## Cleanup

If you deployed only this module in a dedicated workspace:
```bash
terraform destroy
```

## Project layout

```
aws-tf-ct-config-recorder-customization/
├── main.tf           # SQS, Lambdas, IAM, EventBridge, log groups
├── providers.tf      # Required providers and backend config
├── variables.tf      # Inputs (log level, region, exclusions, etc.)
├── locals.tf         # Region mappings and common tags
├── lambda/
│   ├── producer/index.py  # Producer Lambda
│   └── consumer/index.py  # Consumer Lambda
└── cloudformation-deployment/
    ├── ct-config-recorder-customization.yml  # Reference CFN implementation
    └── README.md                             # CFN deployment guide
```

## References

- AWS Config: https://docs.aws.amazon.com/config/
- AWS Control Tower: https://docs.aws.amazon.com/controltower/
- Terraform AWS Provider: https://registry.terraform.io/providers/hashicorp/aws/