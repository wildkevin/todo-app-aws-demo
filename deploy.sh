#!/usr/bin/env bash
# Deploys the To-Do List demo app: DynamoDB table, Lambda function + Function URL, S3 static site.
# Safe to re-run: skips resources that already exist.
set -euo pipefail

export PATH="$HOME/Library/Python/3.10/bin:$PATH"

# A local proxy on this machine intermittently breaks TLS to regional AWS
# endpoints (e.g. sts.us-east-1.amazonaws.com) — bypass it for AWS calls.
export NO_PROXY="*.amazonaws.com"
export no_proxy="*.amazonaws.com"

REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
SUFFIX=$(echo -n "$ACCOUNT_ID" | shasum -a 256 | cut -c1-8)

TABLE_NAME="TodoApp-Todos"
ROLE_NAME="TodoApp-LambdaRole"
FUNCTION_NAME="TodoApp-Handler"
BUCKET_NAME="todo-app-frontend-${SUFFIX}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$SCRIPT_DIR/backend"
FRONTEND_DIR="$SCRIPT_DIR/frontend"
BUILD_DIR="$SCRIPT_DIR/.build"

echo "== Account: $ACCOUNT_ID | Region: $REGION =="

# ---------- 1. DynamoDB table ----------
if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$REGION" >/dev/null 2>&1; then
  echo "[dynamodb] table $TABLE_NAME already exists, skipping"
else
  echo "[dynamodb] creating table $TABLE_NAME"
  aws dynamodb create-table \
    --table-name "$TABLE_NAME" \
    --attribute-definitions AttributeName=id,AttributeType=S \
    --key-schema AttributeName=id,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$REGION" >/dev/null
  aws dynamodb wait table-exists --table-name "$TABLE_NAME" --region "$REGION"
fi
TABLE_ARN=$(aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$REGION" --query 'Table.TableArn' --output text)

# ---------- 2. IAM role for Lambda ----------
if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  echo "[iam] role $ROLE_NAME already exists, skipping"
else
  echo "[iam] creating role $ROLE_NAME"
  aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document '{
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Allow",
        "Principal": {"Service": "lambda.amazonaws.com"},
        "Action": "sts:AssumeRole"
      }]
    }' >/dev/null

  aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

  aws iam put-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-name "TodoAppDynamoDBAccess" \
    --policy-document "{
      \"Version\": \"2012-10-17\",
      \"Statement\": [{
        \"Effect\": \"Allow\",
        \"Action\": [\"dynamodb:PutItem\", \"dynamodb:GetItem\", \"dynamodb:Scan\", \"dynamodb:UpdateItem\", \"dynamodb:DeleteItem\"],
        \"Resource\": \"${TABLE_ARN}\"
      }]
    }"

  echo "[iam] waiting for role propagation..."
  sleep 10
fi
ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)

# ---------- 3. Lambda function ----------
mkdir -p "$BUILD_DIR"
cp "$BACKEND_DIR/handler.py" "$BUILD_DIR/"
(cd "$BUILD_DIR" && rm -f function.zip && zip -q function.zip handler.py)

if aws lambda get-function --function-name "$FUNCTION_NAME" --region "$REGION" >/dev/null 2>&1; then
  echo "[lambda] function $FUNCTION_NAME already exists, updating code"
  aws lambda update-function-code \
    --function-name "$FUNCTION_NAME" \
    --zip-file "fileb://$BUILD_DIR/function.zip" \
    --region "$REGION" >/dev/null
else
  echo "[lambda] creating function $FUNCTION_NAME"
  aws lambda create-function \
    --function-name "$FUNCTION_NAME" \
    --runtime python3.12 \
    --handler handler.handler \
    --role "$ROLE_ARN" \
    --zip-file "fileb://$BUILD_DIR/function.zip" \
    --environment "Variables={TABLE_NAME=$TABLE_NAME}" \
    --timeout 10 \
    --region "$REGION" >/dev/null
  aws lambda wait function-active --function-name "$FUNCTION_NAME" --region "$REGION"
fi

# ---------- 4. S3 bucket (create first so we know its website origin for CORS) ----------
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
  echo "[s3] bucket $BUCKET_NAME already exists, skipping creation"
else
  echo "[s3] creating bucket $BUCKET_NAME"
  aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$REGION" >/dev/null
fi

aws s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --public-access-block-configuration BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false

aws s3 website "s3://$BUCKET_NAME/" --index-document index.html

aws s3api put-bucket-policy --bucket "$BUCKET_NAME" --policy "{
  \"Version\": \"2012-10-17\",
  \"Statement\": [{
    \"Sid\": \"PublicReadGetObject\",
    \"Effect\": \"Allow\",
    \"Principal\": \"*\",
    \"Action\": \"s3:GetObject\",
    \"Resource\": \"arn:aws:s3:::${BUCKET_NAME}/*\"
  }]
}"

WEBSITE_ORIGIN="http://${BUCKET_NAME}.s3-website-${REGION}.amazonaws.com"
if [ "$REGION" != "us-east-1" ]; then
  WEBSITE_ORIGIN="http://${BUCKET_NAME}.s3-website.${REGION}.amazonaws.com"
fi

# ---------- 5. Function URL with CORS locked to the S3 site origin ----------
if aws lambda get-function-url-config --function-name "$FUNCTION_NAME" --region "$REGION" >/dev/null 2>&1; then
  echo "[lambda] function URL already exists, updating CORS origin"
  aws lambda update-function-url-config \
    --function-name "$FUNCTION_NAME" \
    --auth-type NONE \
    --cors "{\"AllowOrigins\":[\"${WEBSITE_ORIGIN}\"],\"AllowMethods\":[\"GET\"],\"AllowHeaders\":[\"content-type\"]}" \
    --region "$REGION" >/dev/null
else
  echo "[lambda] creating function URL"
  aws lambda create-function-url-config \
    --function-name "$FUNCTION_NAME" \
    --auth-type NONE \
    --cors "{\"AllowOrigins\":[\"${WEBSITE_ORIGIN}\"],\"AllowMethods\":[\"GET\"],\"AllowHeaders\":[\"content-type\"]}" \
    --region "$REGION" >/dev/null

  # Since Oct 2025, function URLs need BOTH InvokeFunctionUrl and InvokeFunction
  # permissions on the resource policy (previously InvokeFunctionUrl alone worked).
  aws lambda add-permission \
    --function-name "$FUNCTION_NAME" \
    --action lambda:InvokeFunctionUrl \
    --statement-id FunctionURLAllowPublicAccess \
    --principal "*" \
    --function-url-auth-type NONE \
    --region "$REGION" >/dev/null

  aws lambda add-permission \
    --function-name "$FUNCTION_NAME" \
    --action lambda:InvokeFunction \
    --statement-id UrlPolicyInvokeFunction \
    --principal "*" \
    --invoked-via-function-url \
    --region "$REGION" >/dev/null
fi

FUNCTION_URL=$(aws lambda get-function-url-config --function-name "$FUNCTION_NAME" --region "$REGION" --query 'FunctionUrl' --output text)
FUNCTION_URL="${FUNCTION_URL%/}"

# ---------- 6. Upload frontend, wired to the live Function URL ----------
echo "[frontend] writing config.js with API_BASE_URL=$FUNCTION_URL"
cat > "$FRONTEND_DIR/config.js" <<EOF
window.API_BASE_URL = "${FUNCTION_URL}";
EOF

aws s3 sync "$FRONTEND_DIR" "s3://$BUCKET_NAME/" --exclude ".*"

echo ""
echo "================================================================"
echo " Deploy complete"
echo " Website URL:      ${WEBSITE_ORIGIN}"
echo " Lambda Function URL: ${FUNCTION_URL}"
echo " DynamoDB table:   ${TABLE_NAME}"
echo "================================================================"
