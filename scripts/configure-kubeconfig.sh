#!/usr/bin/env bash
set -euo pipefail

SERVER_IP="${1:-127.0.0.1}"
SOURCE="/etc/rancher/k3s/k3s.yaml"
DEST="${HOME}/.kube/config-k3s-homelab"

if [[ ! -f "${SOURCE}" ]]; then
  echo "No existe ${SOURCE}. ¿K3s está instalado?"
  exit 1
fi

mkdir -p "${HOME}/.kube"
sudo sed "s/127.0.0.1/${SERVER_IP}/g" "${SOURCE}" > "${DEST}"
chmod 600 "${DEST}"

echo "Kubeconfig creado: ${DEST}"
echo "Actívalo con:"
echo "  export KUBECONFIG=\"${DEST}\""
