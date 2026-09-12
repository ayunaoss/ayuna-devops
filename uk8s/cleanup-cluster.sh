#!/bin/bash

set -euo pipefail

SCRIPT_BASE_DIR=$(dirname "$(realpath "$0")")
source $SCRIPT_BASE_DIR/config.sh

if [ -z "$MASTER_NODE" ] || [ -z "${WORKER_NODES[*]}" ]; then
    echo "❌ Error: MASTER_NODE or WORKER_NODES not set in config.sh"
    exit 1
fi

echo "🧹 Cleaning up uk8s cluster and Multipass VMs..."

# Define VM names
NODES=("$MASTER_NODE" "${WORKER_NODES[@]}")

# Delete Multipass instances
for NODE in "${NODES[@]}"; do
    echo "🗑️ Deleting VM: $NODE"
    multipass delete --purge "$NODE" || echo "⚠️ $NODE not found"
done

# Remove kubeconfig context
if [ -f ~/.kube/config ] && grep -q "$KUBECTL_CTX" ~/.kube/config; then
    echo "🧽 Removing uk8s context from kubeconfig..."
    kubectl config delete-context "$KUBECTL_CTX" || true
    kubectl config unset users.uk8s
    kubectl config unset clusters.uk8s
fi

echo "✅ Cleanup complete!"
