import boto3
import os
import logging
import json

def lambda_handler(event, context):
    """
    Producer Lambda function that processes Control Tower events and Lambda update events.
    Sends messages to SQS queue for Consumer Lambda to process.
    """
    LOG_LEVEL = os.getenv('LOG_LEVEL', 'INFO')
    logging.getLogger().setLevel(LOG_LEVEL)
    
    try:
        logging.info('Event Data: ')
        logging.info(event)
        sqs_url = os.getenv('SQS_URL')
        excluded_accounts = os.getenv('EXCLUDED_ACCOUNTS', '')
        logging.info(f'Excluded Accounts: {excluded_accounts}')
        sqs_client = boto3.client('sqs')
        
        # Check if this is an EventBridge triggered event
        is_eb_triggered = 'source' in event
        logging.info(f'Is EventBridge Triggered: {str(is_eb_triggered)}')
        
        if not is_eb_triggered:
            logging.info("No EventBridge source found in event")
            return {'statusCode': 200}
        
        event_source = event['source']
        logging.info(f'Event Source: {event_source}')
        
        # Process Control Tower events
        if event_source == 'aws.controltower':
            event_name = event['detail']['eventName']
            logging.info(f'Control Tower Event Name: {event_name}')
            
            if event_name == 'UpdateManagedAccount':    
                account = event['detail']['serviceEventDetails']['updateManagedAccountStatus']['account']['accountId']
                logging.info(f'Overriding config recorder for SINGLE account: {account}')
                override_config_recorder(excluded_accounts, sqs_url, account, 'controltower')
            elif event_name == 'CreateManagedAccount':  
                account = event['detail']['serviceEventDetails']['createManagedAccountStatus']['account']['accountId']
                logging.info(f'Overriding config recorder for SINGLE account: {account}')
                override_config_recorder(excluded_accounts, sqs_url, account, 'controltower')
            elif event_name == 'UpdateLandingZone':
                logging.info('Overriding config recorder for ALL accounts due to UpdateLandingZone event')
                override_config_recorder(excluded_accounts, sqs_url, '', 'controltower')
        
        # Process Lambda update events
        elif event_source == 'aws.lambda':
            event_name = event['detail']['eventName']
            logging.info(f'Lambda Event Name: {event_name}')
            
            # Check if this is a Lambda function creation event
            if event_name == 'CreateFunction20150331':
                logging.info('Overriding config recorder for ALL accounts due to Lambda function creation')
                override_config_recorder(excluded_accounts, sqs_url, '', 'lambda-create')
            # Check if this is a Lambda function configuration update event
            elif event_name == 'UpdateFunctionConfiguration20150331v2':
                logging.info('Overriding config recorder for ALL accounts due to Lambda function configuration update')
                override_config_recorder(excluded_accounts, sqs_url, '', 'lambda-config-update')
    
        else:
            logging.info(f"No matching event source found: {event_source}")
        
        logging.info('Execution Successful')
        return {'statusCode': 200}
    
    except Exception as e:
        exception_type = e.__class__.__name__
        exception_message = str(e)
        logging.exception(f'{exception_type}: {exception_message}')
        raise e

def override_config_recorder(excluded_accounts, sqs_url, account, event):
    """
    Override config recorder by sending messages to SQS for each account/region combination.
    
    Args:
        excluded_accounts: Comma-separated string of account IDs to exclude
        sqs_url: SQS queue URL
        account: Specific account ID (empty string for all accounts)
        event: Event type (controltower, lambda-update, etc.)
    """
    try:
        client = boto3.client('cloudformation')
        paginator = client.get_paginator('list_stack_instances')
        
        if account == '':
            page_iterator = paginator.paginate(StackSetName='AWSControlTowerBP-BASELINE-CONFIG')
        else:
            page_iterator = paginator.paginate(StackSetName='AWSControlTowerBP-BASELINE-CONFIG', StackInstanceAccount=account)
            
        sqs_client = boto3.client('sqs')
        for page in page_iterator:
            logging.info(page)
            for item in page['Summaries']:
                account_id = item['Account']
                region = item['Region']
                send_message_to_sqs(event, account_id, region, excluded_accounts, sqs_client, sqs_url)
                
    except Exception as e:
        exception_type = e.__class__.__name__
        exception_message = str(e)
        logging.exception(f'{exception_type}: {exception_message}')

def send_message_to_sqs(event, account, region, excluded_accounts, sqs_client, sqs_url):
    """
    Send message to SQS queue for processing by Consumer Lambda.
    
    Args:
        event: Event type
        account: Account ID
        region: AWS region
        excluded_accounts: Comma-separated string of excluded account IDs
        sqs_client: SQS client
        sqs_url: SQS queue URL
    """
    try:
        # Parse excluded accounts string into list
        excluded_list = []
        if excluded_accounts:
            # Handle both comma-separated and space-separated formats
            excluded_list = [acc.strip() for acc in excluded_accounts.replace(',', ' ').split() if acc.strip()]
        
        if account not in excluded_list:
            sqs_msg = json.dumps({
                "Account": account,
                "Region": region,
                "Event": event
            })
            response = sqs_client.send_message(QueueUrl=sqs_url, MessageBody=sqs_msg)
            logging.info(f'Message sent to SQS: {sqs_msg}')
        else:    
            logging.info(f'Account excluded: {account}')
    except Exception as e:
        exception_type = e.__class__.__name__
        exception_message = str(e)
        logging.exception(f'{exception_type}: {exception_message}')

