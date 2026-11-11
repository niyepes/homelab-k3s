#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Ejecuta este script con sudo: sudo $0"
  exit 1
fi

if ! command -v systemctl >/dev/null 2>&1; then
  echo "Este script requiere systemd."
  exit 1
fi

if [[ -f /etc/rancher/k3s/config.yaml ]]; then
  echo "Ya existe /etc/rancher/k3s/config.yaml; no lo sobrescribiré."
  echo "Revísalo manualmente antes de continuar."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

mkdir -p /srv/homelab/k3s-storage
mkdir -p /etc/rancher/k3s
install -m 0600 "${PROJECT_DIR}/infrastructure/k3s/config.yaml.example" /etc/rancher/k3s/config.yaml

echo "Instalando K3s desde el canal stable..."
curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=stable sh -

echo
echo "K3s instalado. Comprueba:"
echo "  sudo k3s kubectl get nodes -o wide"
echo "  sudo k3s kubectl get storageclass"
