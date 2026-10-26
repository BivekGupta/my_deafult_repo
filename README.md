
I. URL Shortner Architecture

The system is divided into two primary paths as shown in the design:
a) Shorten Path (POST /shorten): The user's browser submits a long URL payload. It hits Amazon Route 53 -> Amazon CloudFront -> Amazon API Gateway, which triggers the backend AWS Lambda function. The function generates a unique random string ID (shortId), writes the map into Amazon DynamoDB (TableName: URLMapping, Partition Key: shortId), and returns an HTTP 201 Created response.

b) Redirect Path (GET /{shortId}): The user requests a short link. Traffic follows the same ingress route. The AWS Lambda function issues a GetItem read operation to DynamoDB. If found, it returns an HTTP 301 Moved Permanently redirect response with the Location header populated with the original long URL.

II. RunBook Compilation Generation

To bundle all codebase specifications cleanly for portability, the complete structural project architecture payload file is compiled via Python implementation and Terraform hcl configuration.
Here are your files: lambda_function.py, main.tf, test_integration.py.

a) Prototype Deployment and Execution Pipeline

To implement and deploy this architecture locally or directly onto your AWS infrastructure, execute the following commands in sequence:

1. Set Up the Local Project Directory Structure
Initialize a new environment and download the dependencies:bash
mkdir serverless-url-shortener && cd serverless-url-shortener
npm install -g aws-cdk
cdk init app --language python
source .venv/bin/activate
pip install -r requirements.txt

2. Copy the Source Elements
Ensure your code structures match the generated components inside the package framework:
	• Application Logic: Placed in app/lambda_function.py
	• Infrastructure Stack: Placed in main.tf
	• Integration Tests: Placed in tests/test_integration.py

3. Deploy the application and infrastructure
Authenticate to your AWS account and execute the jenkinsfile to run all scripts using Jenkins tool

4. Execute Automated Integration Tests
Set the baseline target URL parameter returned by your infrastructure build, then run the validation suites:bash
export BASE_API_URL="https://<your-distribution-id>.cloudfront.net"
pip install pytest requests
pytest tests/test_integration.py -v

**Architecture**

<img width="999" height="515" alt="Architecture" src="https://github.com/user-attachments/assets/b6311c08-e601-453b-87de-f4bf4f056577" />


 
