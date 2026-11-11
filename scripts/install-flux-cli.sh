#!/usr/bin/env bash
set -euo pipefail

if ! command -v curl >/dev/null 2>&1; then
  echo "Instala curl primero: sudo apt-get update && sudo apt-get install -y curl"
  exit 1
fi

echo "Instalando Flux CLI según el método oficial..."
curl -s https://fluxcd.io/install.sh | sudo bash

echo
flux --version
