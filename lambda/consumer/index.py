import boto3
import json
import logging
import botocore.exceptions
import os

def lambda_handler(event, context):
    """
    Consumer Lambda function that processes SQS messages and updates Config recorder settings.
    Assumes AWSControlTowerExecution role in target accounts to override Config recorder configuration.
    """
    LOG_LEVEL = os.getenv('LOG_LEVEL', 'INFO')
    logging.getLogger().setLevel(LOG_LEVEL)
    
    try:
        logging.info(f'Event: {str(event).replace(chr(10), "").replace(chr(13), "")}')
        
        # Parse SQS message
        body = json.loads(event['Records'][0]['body'])
        account_id = body['Account']
        aws_region = body['Region']
        event_type = body['Event']
        
        logging.info(f'Extracted Event: {str(event_type).replace(chr(10), "").replace(chr(13), "")}')
        logging.info(f'Extracted Account: {str(account_id).replace(chr(10), "").replace(chr(13), "")}')
        logging.info(f'Extracted Region: {str(aws_region).replace(chr(10), "").replace(chr(13), "")}')

        
        # Log boto3 versions for debugging
        bc = botocore.__version__
        b3 = boto3.__version__
        logging.info(f'Botocore : {bc}')
        logging.info(f'Boto3 : {b3}')
        
        # Assume role in target account
        try:
            sts_session = assume_role(account_id)
            logging.info(f'Successfully assumed role in account: {account_id}')
        except Exception as e:
            logging.warning(f"Couldn't assume role for account {account_id} in region {aws_region}, skipping. Error: {str(e)}")
            return {'statusCode': 200, 'message': f'Skipped account {account_id} due to role assumption failure'}
        
        # Create Config service client for target account/region
        configservice = sts_session.client('config', region_name=aws_region)
        
        # Get existing configuration recorder
        configrecorder = configservice.describe_configuration_recorders()
        
        # Determine recorder name (use existing or default)
        recorder_name = 'aws-controltower-BaselineConfigRecorder'
        if configrecorder and 'ConfigurationRecorders' in configrecorder and len(configrecorder['ConfigurationRecorders']) > 0:
            recorder_name = configrecorder['ConfigurationRecorders'][0]['name']
            logging.info(f'Using existing recorder name: {recorder_name}')
        
        # Update Config recorder with optimized settings
        update_config_recorder(configservice, recorder_name, account_id, aws_region, event_type)
        
        return {'statusCode': 200}
    
    except Exception as e:
        exception_type = e.__class__.__name__
        exception_message = str(e)
        logging.exception(f'{exception_type}: {exception_message}')
        raise e

def assume_role(account_id, role='AWSControlTowerExecution'):
    """
    Assume AWSControlTowerExecution role in target account.
    
    Args:
        account_id: Target AWS account ID
        role: IAM role name to assume (default: AWSControlTowerExecution)
    
    Returns:
        boto3.Session: Session with assumed role credentials
    """
    try:
        STS = boto3.client("sts")
        curr_account = STS.get_caller_identity()['Account']
        
        if curr_account != account_id:
            part = STS.get_caller_identity()['Arn'].split(":")[1]
            role_arn = 'arn:' + part + ':iam::' + account_id + ':role/' + role
            ses_name = str(account_id + '-' + role)
            
            response = STS.assume_role(RoleArn=role_arn, RoleSessionName=ses_name)
            sts_session = boto3.Session(
                aws_access_key_id=response['Credentials']['AccessKeyId'],
                aws_secret_access_key=response['Credentials']['SecretAccessKey'],
                aws_session_token=response['Credentials']['SessionToken'])
            return sts_session
        else:
            # Same account, use current session
            return boto3.Session()
            
    except botocore.exceptions.ClientError as exe:
        logging.error('Unable to assume role')
        raise exe

def update_config_recorder(configservice, recorder_name, account_id, aws_region, event_type):
    """
    Update Config recorder with cost-optimized settings.
    
    Args:
        configservice: Config service client for target account/region
        recorder_name: Name of the Config recorder
        account_id: Target account ID
        aws_region: Target AWS region
        event_type: Type of event triggering the update
    """
    try:
        role_arn = 'arn:aws:iam::' + account_id + ':role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig'
        
        # Get region-specific resources from environment variables
        region_resource_types_mapping = json.loads(os.getenv('REGION_RESOURCE_TYPES_MAPPING', '{}'))
        region_exclusions_mapping = json.loads(os.getenv('REGION_EXCLUSIONS_MAPPING', '{}'))
        
        # Get region-specific resources for the current target region
        region_continuous_resources = region_resource_types_mapping.get(aws_region, {}).get('ResourceTypes', [])
        region_exclusions = region_exclusions_mapping.get(aws_region, {}).get('ResourceTypes', [])
        
        # Get configuration from environment variables
        CONFIG_RECORDER_STRATEGY = os.getenv('CONFIG_RECORDER_STRATEGY', 'EXCLUSION')
        CONFIG_RECORDER_DEFAULT_RECORDING_FREQUENCY = os.getenv('CONFIG_RECORDER_DEFAULT_RECORDING_FREQUENCY', 'DAILY')
        
        logging.info(f'Applying {CONFIG_RECORDER_STRATEGY} and {CONFIG_RECORDER_DEFAULT_RECORDING_FREQUENCY} strategy for {aws_region}')
        logging.info(f'Resources set to CONTINUOUS recording: {region_continuous_resources}')
        logging.info(f'Resources EXCLUDED from recording: {region_exclusions}')
        
        config_recorder = {
                'name': recorder_name,
                'roleARN': role_arn,
                'recordingGroup': {
                    'allSupported': False,
                    'includeGlobalResourceTypes': False,
                    'exclusionByResourceTypes': {
                        'resourceTypes': region_exclusions
                    },
                    'recordingStrategy': {
                        'useOnly': 'EXCLUSION_BY_RESOURCE_TYPES'
                    }
                },
                'recordingMode': {
                    'recordingFrequency': CONFIG_RECORDER_DEFAULT_RECORDING_FREQUENCY,
                    'recordingModeOverrides': [
                        {
                            'description': 'CONTINUOUS_OVERRIDE',
                            'resourceTypes': region_continuous_resources,
                            'recordingFrequency': 'CONTINUOUS'
                        }
                    ] if region_continuous_resources else []
                }
        }
        
        response = configservice.put_configuration_recorder(ConfigurationRecorder=config_recorder)
        logging.info(f'Response for put_configuration_recorder: {response}')
        
    except botocore.exceptions.ClientError as exe:
        logging.error(f'Unable to Update Config Recorder for Account {account_id} and Region {aws_region}')
        raise exe