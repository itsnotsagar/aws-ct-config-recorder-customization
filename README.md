# AWS Control Tower Config Recorder Customization

Automatically optimizes AWS Config recorder settings for landing zones managed by **AWS Control Tower** and **Account Factory for Terraform (AFT)** to reduce costs while maintaining compliance visibility.

## Overview

**Control Tower Default Behavior:**
AWS Control Tower creates Config recorders that record **all supported resources continuously** across all managed accounts and regions (except IAM global resources which are recorded only in the home region). This default configuration can result in high AWS Config costs, especially for environments with frequent resource changes.

**This Solution:**
This CloudFormation template automatically overrides Control Tower's default Config recorder settings with cost-optimized configurations. It deploys Lambda functions that detect Control Tower account creation/update events and reconfigure Config recorders to use:

**Cost Optimization Features:**
- **Daily recording frequency** instead of continuous recording (significantly reduces configuration item charges)
- **Exclusion-based recording** to skip expensive, high-change resources like backup recovery points and compliance data
- **Selective continuous recording** only for critical resources that require real-time monitoring (IAM, Route53, etc.)
- **Region-specific resource mappings** that can be customized by modifying the template mappings
- **Automatic application** to new accounts created through Control Tower or AFT

## Architecture

- **Producer Lambda**: Detects Control Tower events and queues processing tasks
- **Consumer Lambda**: Assumes the `AWSControlTowerExecution` role in target accounts to override Config recorder settings
- **SQS Queue**: Manages processing queue between producer and consumer
- **EventBridge Rule**: Triggers on Control Tower events (CreateManagedAccount, UpdateManagedAccount, UpdateLandingZone)

**Cross-Account Access:**
The Consumer Lambda uses the `AWSControlTowerExecution` role (automatically created by Control Tower in all managed accounts) to gain the necessary permissions to modify Config recorder settings across the organization.

## How It Works

### Initial Deployment
When the CloudFormation stack is **first deployed**, the Producer Lambda is automatically triggered via a custom resource and will:
1. Query all existing Control Tower managed accounts across all regions
2. Send messages to the SQS queue for each account/region combination
3. The Consumer Lambda processes these messages and overrides **all existing Config recorders** managed by Control Tower

### Ongoing Operations
After initial deployment, the system operates automatically based on Control Tower events:

**Event Triggers:**
- **`CreateManagedAccount`**: When Control Tower creates a new account (including AFT provisioned accounts)
- **`UpdateManagedAccount`**: When Control Tower updates an existing managed account
- **`UpdateLandingZone`**: When Control Tower landing zone is updated (affects all accounts)

**Workflow:**
1. **EventBridge Rule** detects Control Tower events and triggers the Producer Lambda
2. **Producer Lambda** identifies the target account(s) and region(s) based on the event type
3. **Producer Lambda** sends messages to the SQS queue with account/region details
4. **Consumer Lambda** is triggered by SQS messages and assumes the `AWSControlTowerExecution` role in each target account
5. **Consumer Lambda** overrides the Config recorder settings with the cost-optimized configuration

## Parameters

| Parameter | Description | Default | Values |
|-----------|-------------|---------|---------|
| `CloudFormationVersion` | Version to force stack updates | `1` | Any string |
| `ExcludedAccounts` | Accounts to skip | Management, Audit, Log Archive | Account ID list |
| `ConfigRecorderStrategy` | Recording strategy | `EXCLUSION` | `EXCLUSION` |
| `ConfigRecorderDefaultRecordingFrequency` | Default frequency | `DAILY` | `DAILY` |

## Region Mappings

### RegionResourceTypes
Resources recorded **continuously** instead of daily:
- **us-east-1**: IAM, Route53, WAF, CloudFront, ECR Public
- **us-west-2, ap-south-1, ap-northeast-2, eu-west-1**: EC2, VPC, ELB resources

### RegionExclusions  
Resources **excluded** from recording:
- **us-east-1**: Config compliance, Backup recovery points, Global Accelerator
- **Other regions**: Above + IAM, Route53, WAF, CloudFront, ECR Public, Global Accelerator

## Recording Strategy

- **EXCLUSION**: Records all resources except those in RegionExclusions
- RegionResourceTypes resources are recorded continuously instead of daily

## Deployment

### Option 1: AWS CLI

```bash
aws cloudformation create-stack \
  --stack-name ct-config-recorder-customization \
  --template-body file://ct-config-recorder-customization.yml \
  --parameters ParameterKey=ExcludedAccounts,ParameterValue="['123456789012','234567890123']" \
  --capabilities CAPABILITY_IAM
```

Replace the account IDs with your management, audit, and log archive accounts.

### Option 2: AWS Console (Manual)

1. **Navigate to CloudFormation Console**
   - Go to AWS CloudFormation in your Control Tower home region
   - Click "Create stack" → "With new resources (standard)"

2. **Upload Template**
   - Select "Upload a template file"
   - Choose the `ct-config-recorder-customization.yml` file
   - Click "Next"

3. **Configure Stack Parameters**
   - **Stack name**: `ct-config-recorder-customization`
   - **CloudFormationVersion**: Leave as `1` (increment for updates)
   - **ExcludedAccounts**: Enter your account IDs as a list, e.g., `['123456789012','234567890123']`
   - **ConfigRecorderStrategy**: `EXCLUSION` (only option)
   - **ConfigRecorderDefaultRecordingFrequency**: `DAILY` (only option)
   - Click "Next"

4. **Configure Stack Options**
   - Add tags if desired (optional)
   - Leave other settings as default
   - Click "Next"

5. **Review and Deploy**
   - Review all settings
   - Check "I acknowledge that AWS CloudFormation might create IAM resources"
   - Click "Submit"

The stack will create Lambda functions, SQS queue, EventBridge rules, and IAM roles needed for automatic Config recorder customization.

## Customization

### Add Resources for Continuous Recording
```yaml
RegionResourceTypes:
  us-east-1:
    ResourceTypes:
      - AWS::IAM::User
      - AWS::RDS::DBInstance  # Add this
```

### Add Resources to Exclude
```yaml
RegionExclusions:
  us-east-1:
    ResourceTypes:
      - AWS::Config::ResourceCompliance
      - AWS::S3::Bucket  # Add this
```

### Add New Region
Add the region to both mappings and update the Consumer Lambda environment variables.

## Monitoring

Check CloudWatch logs:
- Producer Lambda: `/aws/lambda/ct-config-recorder-customization-ProducerLambda-{RandomString}`
- Consumer Lambda: `/aws/lambda/ct-config-recorder-customization-ConsumerLambda-{RandomString}`

Note: Replace `{RandomString}` with the actual suffix generated by CloudFormation, or find the exact names in the Lambda console.

## References

This solution is derived from the AWS blog post: [Customize AWS Config resource tracking in AWS Control Tower environment](https://aws.amazon.com/blogs/mt/customize-aws-config-resource-tracking-in-aws-control-tower-environment/)

