#!/bin/bash
# =============================================================================
# S3 Bucket List Script
# =============================================================================
# Lists all S3 buckets in Floci
# =============================================================================

set -e

# Load environment variables from .env if it exists
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

# Configuration with defaults
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-test}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-test}
AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-east-1}
ENDPOINT="http://floci:4566"
NETWORK="scr-local_scr-local"

docker run --rm --network "$NETWORK" \
    -e AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
    -e AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
    -e AWS_DEFAULT_REGION="$AWS_DEFAULT_REGION" \
    amazon/aws-cli --endpoint-url="$ENDPOINT" s3 ls
