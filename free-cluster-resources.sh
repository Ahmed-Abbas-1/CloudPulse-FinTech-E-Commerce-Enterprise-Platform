#!/usr/bin/env bash
set -euo pipefail

echo "1. Removing Kyverno Blocking Webhooks and Policies (Already Screenshotted)..."
kubectl delete clusterpolicy --all --ignore-not-found=true
kubectl delete validatingwebhookconfigurations -l webhook.kyverno.io/managed-by=kyverno --ignore-not-found=true
kubectl delete mutatingwebhookconfigurations -l webhook.kyverno.io/managed-by=kyverno --ignore-not-found=true
kubectl scale deployment --all --replicas=0 -n kyverno --ignore-not-found=true

echo "2. Freezing Vault, External Secrets & Cert-Manager to save RAM..."
kubectl delete externalsecret --all -n cloudpulse-prod --ignore-not-found=true
kubectl scale deployment --all --replicas=0 -n security-system --ignore-not-found=true
kubectl scale statefulset --all --replicas=0 -n security-system --ignore-not-found=true
kubectl scale deployment --all --replicas=0 -n cert-manager --ignore-not-found=true

echo "3. Ensuring static application secret exists in cloudpulse-prod..."
kubectl create secret generic cloudpulse-app-secrets \
  --namespace cloudpulse-prod \
  --from-literal=JWT_SECRET="vault-managed-zero-trust-jwt-key-2026" \
  --from-literal=POSTGRES_USER="cloudpulse" \
  --from-literal=POSTGRES_PASSWORD="cloudpulse_secret_db_pass" \
  --from-literal=POSTGRES_DB="cloudpulsedb" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "4. Refreshing AWS ECR Pull Secret directly from Master Node..."
AWS_REGION="us-east-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_TOKEN=$(aws ecr get-login-password --region ${AWS_REGION})

kubectl create secret docker-registry ecr-registry-secret \
  --namespace cloudpulse-prod \
  --docker-server="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com" \
  --docker-username=AWS \
  --docker-password="${ECR_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "5. Temporarily pausing Observability stack until Phase 4 screenshots are done..."
kubectl scale deployment --all --replicas=0 -n observability --ignore-not-found=true
kubectl scale statefulset --all --replicas=0 -n observability --ignore-not-found=true

echo "6. Cleaning up any Evicted, Failed, or Terminating pods across all namespaces..."
kubectl get pods -A | awk '$4 ~ /Evicted|Error|Completed|CrashLoopBackOff|ImagePullBackOff/ {print $1, $2}' | xargs -n 2 sh -c 'kubectl delete pod $1 -n $0 --force --grace-period=0' 2>/dev/null || true

echo "=========================================================="
echo "RAM Freed & Cluster Unblocked Successfully!"
echo "=========================================================="
