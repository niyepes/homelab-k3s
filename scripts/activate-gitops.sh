#!/usr/bin/env bash
set -euo pipefail

BRANCH="${1:-main}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

if [[ ! -d .git ]]; then
  echo "Ejecuta este script desde una copia clonada del repositorio Git."
  exit 1
fi

git pull --rebase origin "${BRANCH}"
cp clusters/local/kustomization.yaml.template clusters/local/kustomization.yaml
git add clusters/local/kustomization.yaml

if git diff --cached --quiet; then
  echo "La configuración raíz ya está actualizada."
else
  git commit -m "chore(flux): reconcile homelab components"
  git push origin "${BRANCH}"
fi

echo "Configuración GitOps publicada."
