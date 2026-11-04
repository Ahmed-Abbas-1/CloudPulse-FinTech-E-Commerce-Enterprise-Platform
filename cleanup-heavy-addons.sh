#!/usr/bin/env bash
set -euo pipefail

echo "1. Removing Kyverno Webhooks and uninstalling Kyverno..."
kubectl delete clusterpolicy --all --ignore-not-found=true
kubectl delete validatingwebhookconfigurations -l webhook.kyverno.io/managed-by=kyverno --ignore-not-found=true
kubectl delete mutatingwebhookconfigurations -l webhook.kyverno.io/managed-by=kyverno --ignore-not-found=true
helm uninstall kyverno -n kyverno 2>/dev/null || true
kubectl delete namespace kyverno --wait=false --ignore-not-found=true

echo "2. Uninstalling Vault, External Secrets Operator, and Cert-Manager..."
kubectl delete externalsecret --all -n cloudpulse-prod --ignore-not-found=true
helm uninstall external-secrets -n security-system 2>/dev/null || true
helm uninstall vault -n security-system 2>/dev/null || true
kubectl delete namespace security-system --wait=false --ignore-not-found=true

helm uninstall cert-manager -n cert-manager 2>/dev/null || true
kubectl delete namespace cert-manager --wait=false --ignore-not-found=true

echo "3. Removing Longhorn Storage completely (Freeing Disk I/O and 3GB+ RAM)..."
kubectl delete pvc --all -n cloudpulse-prod --wait=false --ignore-not-found=true
kubectl delete pvc --all -n observability --wait=false --ignore-not-found=true
helm uninstall longhorn -n longhorn-system 2>/dev/null || true
kubectl delete namespace longhorn-system --wait=false --ignore-not-found=true

# Remove finalizers if any Longhorn CRDs hang during deletion
for crd in $(kubectl get crd -o name | grep longhorn.io || true); do
    kubectl patch "$crd" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
    kubectl delete "$crd" --wait=false 2>/dev/null || true
done

echo "4. Temporarily pausing Observability stack (Prometheus/Grafana/Loki) until Stage B..."
kubectl scale deployment --all --replicas=0 -n observability 2>/dev/null || true
kubectl scale statefulset --all --replicas=0 -n observability 2>/dev/null || true

echo "5. Refreshing AWS ECR Token so real Microservice Images pull cleanly..."
AWS_REGION="us-east-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_TOKEN=$(aws ecr get-login-password --region ${AWS_REGION})

kubectl create secret docker-registry ecr-registry-secret \
  --namespace cloudpulse-prod \
  --docker-server="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com" \
  --docker-username=AWS \
  --docker-password="${ECR_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "=========================================================="
echo "Heavy Add-ons Removed! RAM & Disk I/O are now wide open."
echo "=========================================================="
