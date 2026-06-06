# src/process_payment.py
import json
import boto3
import os
from datetime import datetime

# Note: In LocalStack, endpoint_url must be specified for clients
endpoint_url = f"http://{os.environ.get('LOCALSTACK_HOSTNAME')}:{os.environ.get('EDGE_PORT')}"
dynamodb = boto3.resource('dynamodb', endpoint_url=endpoint_url)
table = dynamodb.Table(os.environ['DYNAMODB_TABLE_NAME'])


def handler(event, context):
    print(json.dumps(event))

    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = record['s3']['object']['key']

        # Create a transaction ID from the key and current time
        transaction_id = f"{key}-{datetime.utcnow().isoformat()}"

        # Write to DynamoDB
        table.put_item(
            Item={
                'TransactionID': transaction_id,
                'Bucket': bucket,
                'ObjectKey': key,
                'Status': 'PROCESSED',
                'ProcessedAt': datetime.utcnow().isoformat()
            }
        )

        print(f"Processed {key} from {bucket}. TransactionID: {transaction_id}")

    return {'status': 'success'}
