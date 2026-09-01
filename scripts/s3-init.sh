#!/bin/bash
# =============================================================================
# S3 Bucket Initialization Script
# =============================================================================
# Creates private and public S3 buckets in Floci
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
BUCKET_PRIVATE=${AWS_BUCKET_PRIVATE:-scr-private-bucket}
BUCKET_PUBLIC=${AWS_BUCKET_PUBLIC:-scr-public-bucket}
ENDPOINT="http://floci:4566"
NETWORK="scr-local_scr-local"

echo "Creating S3 buckets..."
echo "  Private: $BUCKET_PRIVATE"
echo "  Public:  $BUCKET_PUBLIC"
echo ""

# Create private bucket
docker run --rm --network "$NETWORK" \
    -e AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
    -e AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
    -e AWS_DEFAULT_REGION="$AWS_DEFAULT_REGION" \
    amazon/aws-cli --endpoint-url="$ENDPOINT" \
    s3 mb "s3://$BUCKET_PRIVATE" 2>&1 | grep -v "BucketAlreadyOwnedByYou" || echo "✓ Private bucket ready"

# Create public bucket
docker run --rm --network "$NETWORK" \
    -e AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
    -e AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
    -e AWS_DEFAULT_REGION="$AWS_DEFAULT_REGION" \
    amazon/aws-cli --endpoint-url="$ENDPOINT" \
    s3 mb "s3://$BUCKET_PUBLIC" 2>&1 | grep -v "BucketAlreadyOwnedByYou" || echo "✓ Public bucket ready"

echo ""
echo "✓ S3 buckets initialized successfully"
