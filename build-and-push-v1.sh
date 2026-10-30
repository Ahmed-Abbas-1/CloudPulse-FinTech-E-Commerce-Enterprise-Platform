#!/usr/bin/env bash
set -euo pipefail

if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker $USER
fi

AWS_REGION="us-east-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo "Authenticating with AWS ECR (${ECR_URI})..."
aws ecr get-login-password --region ${AWS_REGION} | sudo docker login --username AWS --password-stdin ${ECR_URI}

SERVICES=("auth-gateway" "catalog-service" "order-service" "notification-worker" "frontend-ui")

for svc in "${SERVICES[@]}"; do
    echo "=================================================="
    echo "Building & Pushing ${svc}:v1.0.0 ..."
    echo "=================================================="
    sudo docker build --provenance=false -t "${ECR_URI}/cloudpulse/${svc}:v1.0.0" "$HOME/cloudpulse-platform/services/${svc}"
    sudo docker push "${ECR_URI}/cloudpulse/${svc}:v1.0.0"
done

# Inject real AWS Account ID into Helm values.yaml automatically
sed -i "s/123456789012/${AWS_ACCOUNT_ID}/g" ~/cloudpulse-platform/helm/cloudpulse-chart/values.yaml
echo "All 5 Microservices pushed to AWS ECR and Helm values.yaml updated!"
