#!/usr/bin/env bash
set -euo pipefail

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl no está instalado o no está en PATH."
  exit 1
fi

echo "Este script crea namespaces y secretos directamente en el clúster."
echo "No guarda las credenciales en archivos del repositorio."
echo

read -r -p "Tailscale OAuth Client ID: " TS_CLIENT_ID
read -r -s -p "Tailscale OAuth Client Secret: " TS_CLIENT_SECRET
echo
read -r -s -p "Contraseña inicial de Grafana: " GRAFANA_PASSWORD
echo

if [[ -z "${TS_CLIENT_ID}" || -z "${TS_CLIENT_SECRET}" || -z "${GRAFANA_PASSWORD}" ]]; then
  echo "No se permiten valores vacíos."
  exit 1
fi

kubectl create namespace tailscale --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

cat > "${TMP_DIR}/values.yaml" <<EOF
oauth:
  clientId: "${TS_CLIENT_ID}"
  clientSecret: "${TS_CLIENT_SECRET}"
EOF

kubectl create secret generic tailscale-oauth \
  --namespace tailscale \
  --from-file=values.yaml="${TMP_DIR}/values.yaml" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic grafana-admin \
  --namespace monitoring \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="${GRAFANA_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

unset TS_CLIENT_ID TS_CLIENT_SECRET GRAFANA_PASSWORD
echo
echo "Secretos creados. No los exportes ni los añadas a Git."
