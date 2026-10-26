import os
import json
import secrets
import string
import boto3
from botocore.exceptions import ClientError

# Initialize AWS SDK Clients
dynamodb = boto3.resource('dynamodb')
TABLE_NAME = os.environ.get('TABLE_NAME', 'URLMapping')
table = dynamodb.Table(TABLE_NAME)

def generate_short_id(length=6):
    """Generates a random cryptographically secure string identifier."""
    chars = string.ascii_letters + string.digits
    return ''.join(secrets.choice(chars) for _ in range(length))

def handler(event, context):
    print("Received event: ", json.dumps(event))
    
    http_method = event.get('httpMethod')
    path_parameters = event.get('pathParameters') or {}
    
    # --- REDIRECT PATH: GET /{shortId} ---
    if http_method == 'GET':
        short_id = path_parameters.get('shortId')
        if not short_id:
            return {'statusCode': 400, 'body': json.dumps({'error': 'Missing shortId'})}
        
        try:
            response = table.get_item(Key={'shortId': short_id})
            if 'Item' in response:
                long_url = response['Item']['longUrl']
                return {
                    'statusCode': 301,
                    'headers': {
                        'Location': long_url,
                        'Cache-Control': 'no-store, must-revalidate'
                    },
                    'body': ''
                }
            else:
                return {'statusCode': 404, 'body': json.dumps({'error': 'URL not found'})}
        except ClientError as e:
            print(e.response['Error']['Message'])
            return {'statusCode': 500, 'body': json.dumps({'error': 'Internal server error'})}

    # --- SHORTEN PATH: POST /shorten ---
    elif http_method == 'POST':
        try:
            body = json.loads(event.get('body') or '{}')
            long_url = body.get('longUrl')
            if not long_url:
                return {'statusCode': 400, 'body': json.dumps({'error': 'Missing longUrl field'})}
            
            # Simple deduplication attempt / generation
            short_id = generate_short_id()
            
            table.put_item(
                Item={
                    'shortId': short_id,
                    'longUrl': long_url
                }
            )
            
            return {
                'statusCode': 201,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'shortId': short_id, 'shortUrl': f"/{short_id}"})
            }
        except Exception as e:
            print("Error processing POST request:", str(e))
            return {'statusCode': 400, 'body': json.dumps({'error': 'Invalid request format'})}

    return {
        'statusCode': 405,
        'body': json.dumps({'error': f'Method {http_method} not allowed'})
    }
