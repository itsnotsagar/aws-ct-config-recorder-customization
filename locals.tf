locals {
  # Region mappings from CloudFormation template - resources for continuous recording by region
  region_continuous_resources = {
    "us-east-1" = [
      "AWS::IAM::User",
      "AWS::Route53::HostedZone",
      "AWS::Route53::HealthCheck",
      "AWS::WAFv2::WebACL",
      "AWS::CloudFront::Distribution",
      "AWS::ECR::PublicRepository"
    ]
    "us-west-2" = [
      "AWS::EC2::Instance",
      "AWS::EC2::VPC",
      "AWS::EC2::Subnet",
      "AWS::EC2::Volume",
      "AWS::EC2::NetworkInterface",
      "AWS::EC2::EIP",
      "AWS::ElasticLoadBalancing::LoadBalancer",
      "AWS::ElasticLoadBalancingV2::LoadBalancer"
    ]
    "ap-south-1" = [
      "AWS::EC2::Instance",
      "AWS::EC2::VPC",
      "AWS::EC2::Subnet",
      "AWS::EC2::Volume",
      "AWS::EC2::NetworkInterface",
      "AWS::EC2::EIP",
      "AWS::ElasticLoadBalancing::LoadBalancer",
      "AWS::ElasticLoadBalancingV2::LoadBalancer"
    ]
    "ap-northeast-2" = [
      "AWS::EC2::Instance",
      "AWS::EC2::VPC",
      "AWS::EC2::Subnet",
      "AWS::EC2::Volume",
      "AWS::EC2::NetworkInterface",
      "AWS::EC2::EIP",
      "AWS::ElasticLoadBalancing::LoadBalancer",
      "AWS::ElasticLoadBalancingV2::LoadBalancer"
    ]
    "eu-west-1" = [
      "AWS::EC2::Instance",
      "AWS::EC2::VPC",
      "AWS::EC2::Subnet",
      "AWS::EC2::Volume",
      "AWS::EC2::NetworkInterface",
      "AWS::EC2::EIP",
      "AWS::ElasticLoadBalancing::LoadBalancer",
      "AWS::ElasticLoadBalancingV2::LoadBalancer"
    ]
  }

  # Region mappings from CloudFormation template - resources to exclude from recording by region
  region_exclusions = {
    "us-east-1" = [
      "AWS::Config::ResourceCompliance",
      "AWS::Backup::RecoveryPoint",
      "AWS::GlobalAccelerator::Listener",
      "AWS::GlobalAccelerator::EndpointGroup",
      "AWS::GlobalAccelerator::Accelerator"
    ]
    "us-west-2" = [
      "AWS::Backup::RecoveryPoint",
      "AWS::Config::ResourceCompliance",
      "AWS::IAM::Role",
      "AWS::IAM::Policy",
      "AWS::IAM::User",
      "AWS::IAM::Group",
      "AWS::Route53::HostedZone",
      "AWS::Route53::HealthCheck",
      "AWS::WAFv2::WebACL",
      "AWS::CloudFront::Distribution",
      "AWS::ECR::PublicRepository"
    ]
    "ap-south-1" = [
      "AWS::Backup::RecoveryPoint",
      "AWS::Config::ResourceCompliance",
      "AWS::IAM::Role",
      "AWS::IAM::Policy",
      "AWS::IAM::User",
      "AWS::IAM::Group",
      "AWS::Route53::HostedZone",
      "AWS::Route53::HealthCheck",
      "AWS::WAFv2::WebACL",
      "AWS::CloudFront::Distribution",
      "AWS::ECR::PublicRepository",
      "AWS::GlobalAccelerator::Listener",
      "AWS::GlobalAccelerator::EndpointGroup",
      "AWS::GlobalAccelerator::Accelerator"
    ]
    "ap-northeast-2" = [
      "AWS::Backup::RecoveryPoint",
      "AWS::Config::ResourceCompliance",
      "AWS::IAM::Role",
      "AWS::IAM::Policy",
      "AWS::IAM::User",
      "AWS::IAM::Group",
      "AWS::Route53::HostedZone",
      "AWS::Route53::HealthCheck",
      "AWS::WAFv2::WebACL",
      "AWS::CloudFront::Distribution",
      "AWS::ECR::PublicRepository",
      "AWS::GlobalAccelerator::Listener",
      "AWS::GlobalAccelerator::EndpointGroup",
      "AWS::GlobalAccelerator::Accelerator"
    ]
    "eu-west-1" = [
      "AWS::Backup::RecoveryPoint",
      "AWS::Config::ResourceCompliance",
      "AWS::IAM::Role",
      "AWS::IAM::Policy",
      "AWS::IAM::User",
      "AWS::IAM::Group",
      "AWS::Route53::HostedZone",
      "AWS::Route53::HealthCheck",
      "AWS::WAFv2::WebACL",
      "AWS::CloudFront::Distribution",
      "AWS::ECR::PublicRepository",
      "AWS::GlobalAccelerator::Listener",
      "AWS::GlobalAccelerator::EndpointGroup",
      "AWS::GlobalAccelerator::Accelerator"
    ]
  }

  # Convert to JSON for Lambda environment variables (matching CloudFormation structure)
  region_continuous_resources_json = jsonencode({
    for region, resources in local.region_continuous_resources : region => {
      ResourceTypes = resources
    }
  })
  region_exclusions_json = jsonencode({
    for region, resources in local.region_exclusions : region => {
      ResourceTypes = resources
    }
  })

  # Common tags to apply to all resources
  common_tags = {
    Module    = "ct-config-recorder-terraform"
    ManagedBy = "terraform"
    Project   = "ct-config-recorder-customization"
  }
}
