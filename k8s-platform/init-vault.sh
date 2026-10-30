#!/usr/bin/env bash
set -euo pipefail

echo "Waiting for Vault pod vault-0 to be running..."
kubectl wait --for=jsonpath='{.status.phase}'=Running pod/vault-0 -n security-system --timeout=120s

INIT_STATUS=$(kubectl exec vault-0 -n security-system -- vault status -format=json 2>/dev/null | jq -r '.initialized')

if [ "$INIT_STATUS" = "false" ]; then
    echo "Initializing HashiCorp Vault..."
    kubectl exec vault-0 -n security-system -- vault operator init \
      -key-shares=1 \
      -key-threshold=1 \
      -format=json > ~/cloudpulse-platform/k8s-platform/.vault-keys.json
    chmod 600 ~/cloudpulse-platform/k8s-platform/.vault-keys.json
fi

UNSEAL_KEY=$(jq -r '.unseal_keys_b64[0]' ~/cloudpulse-platform/k8s-platform/.vault-keys.json)
ROOT_TOKEN=$(jq -r '.root_token' ~/cloudpulse-platform/k8s-platform/.vault-keys.json)

echo "Unsealing HashiCorp Vault..."
kubectl exec vault-0 -n security-system -- vault operator unseal "$UNSEAL_KEY" >/dev/null

echo "Logging into Vault and configuring KV-v2 Secret Engine..."
kubectl exec vault-0 -n security-system -- sh -c "
  export VAULT_TOKEN=${ROOT_TOKEN}
  vault secrets enable -path=secret kv-v2 2>/dev/null || true
  vault kv put secret/cloudpulse/prod \
    JWT_SECRET='vault-managed-zero-trust-jwt-key-2026' \
    POSTGRES_USER='cloudpulse' \
    POSTGRES_PASSWORD='cloudpulse_secret_db_pass' \
    POSTGRES_DB='cloudpulsedb'
"

echo "Creating Vault Token Secret for External Secrets Operator..."
kubectl create secret generic vault-token-secret \
  --namespace security-system \
  --from-literal=token="$ROOT_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "=========================================================="
echo "Vault is Initialized, Unsealed, and Secrets are Stored!"
echo "Vault Root Token (for UI Login): ${ROOT_TOKEN}"
echo "=========================================================="
