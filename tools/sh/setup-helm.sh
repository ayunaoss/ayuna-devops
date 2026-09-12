#!/bin/bash

set -euo pipefail

mkdir -p ~/.local/bin
pushd ~/.local/bin >/dev/null

## Remove existing helm and kubectl-convert binaries
rm -f helm kubectl-convert && sync

## Download and validate kubectl-convert plugin
k8s_rel=$(curl -L -s https://dl.k8s.io/release/stable.txt)
curl -LO "https://dl.k8s.io/release/${k8s_rel}/bin/linux/amd64/kubectl-convert"
curl -LO "https://dl.k8s.io/release/${k8s_rel}/bin/linux/amd64/kubectl-convert.sha256"

echo "$(cat kubectl-convert.sha256) kubectl-convert" | sha256sum --check
chmod +x kubectl-convert
rm -f *.sha256 && sync

curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
USE_SUDO=false HELM_INSTALL_DIR=$HOME/.local/bin ./get_helm.sh
sync && rm -f get_helm.sh

popd >/dev/null
