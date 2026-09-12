#!/bin/bash

set -euo pipefail

SCRIPT_BASE_DIR=$(dirname "$(realpath "$0")")
source $SCRIPT_BASE_DIR/config.sh

if [ -z "$MASTER_NODE" ] || [ -z "${WORKER_NODES[*]}" ]; then
  echo "❌ Error: MASTER_NODE or WORKER_NODES not set in config.sh"
  exit 1
fi

is_microk8s_addon_enabled() {
  local addon="$1"
  multipass exec "$MASTER_NODE" -- microk8s status --format short 2>/dev/null | grep -Fxq "  - ${addon}"
}

echo "🚀 Starting MicroK8s cluster with multipass..."

# Step 1: Generate SSH key if missing
if [ ! -f "$SSH_KEY" ]; then
  echo "🔐 Generating SSH key..."
  ssh-keygen -t rsa -b 4096 -f "$SSH_KEY" -N ""
fi

# Step 2: Install microk8s on each of the nodes
echo "📦 Installing microk8s on all nodes..."
NODES=("$MASTER_NODE" "${WORKER_NODES[@]}")

for NODE in "${NODES[@]}"; do
  # Check if the node already exists
  if multipass list | grep -q "$NODE"; then
    echo "⚠️ Node $NODE already exists. Skipping installation."
    continue
  fi

  echo "📦 Installing on $NODE..."
  multipass launch -n "$NODE" -c $CPU -m $MEM -d $DISK --cloud-init <(
    cat <<EOF
#cloud-config
runcmd:
  - sudo snap install microk8s --classic
  - microk8s status --wait-ready
  - sudo usermod -a -G microk8s ubuntu
  - sudo chown -f -R ubuntu ~/.kube
  - microk8s config > ~/.kube/config
  - chmod 600 ~/.kube/config
users:
  - name: ubuntu
    ssh_authorized_keys:
      - $(cat "$SSH_KEY.pub")
EOF
  )
done

# Step 3: Fetch IP addresses
declare -A NODE_IP_MAP

echo "🌐 Fetching IP addresses for all nodes..."
MASTER_IP=$(multipass info "$MASTER_NODE" | grep IPv4 | awk '{print $2}')
UK8S_NETCLS=$(echo "$MASTER_IP" | cut -d'.' -f1-3)
UK8S_HOST_IP="${UK8S_NETCLS}.1"

NODE_IP_MAP["$MASTER_NODE"]=$MASTER_IP

for NODE in "${WORKER_NODES[@]}"; do
  NODE_IP_MAP["$NODE"]=$(multipass info "$NODE" | grep IPv4 | awk '{print $2}')
done

for NODE in "${!NODE_IP_MAP[@]}"; do
  echo "Node: $NODE, IP: ${NODE_IP_MAP[$NODE]}"
done

# Step 4: Add ip <-> hostname mapping to /etc/hosts for all nodes
echo "📝 Updating /etc/hosts on all nodes..."
for NODE in "${!NODE_IP_MAP[@]}"; do

  if multipass exec "$NODE" -- grep -q "[[:space:]]uk8s-host\.local" /etc/hosts; then
    echo "Updating existing uk8s-host.local entry for $NODE"
    multipass exec "$NODE" -- sudo sed -i "/[[:space:]]uk8s-host\.local/ s/^[^[:space:]]*/$UK8S_HOST_IP/" /etc/hosts
  else
    echo "Adding new uk8s-host.local entry for $NODE"
    multipass exec "$NODE" -- bash -c "echo '$UK8S_HOST_IP uk8s-host.local' | sudo tee -a /etc/hosts"
  fi

  for ND in "${!NODE_IP_MAP[@]}"; do
    ND_IP="${NODE_IP_MAP[$ND]}"

    if multipass exec "$NODE" -- grep -q "[[:space:]]${ND}\.local" /etc/hosts; then
      echo "Updating existing ${ND}.local entry for $NODE"
      multipass exec "$NODE" -- sudo sed -i "/[[:space:]]${ND}\.local/ s/^[^[:space:]]*/$ND_IP/" /etc/hosts
    else
      echo "Adding new ${ND}.local entry for $NODE"
      multipass exec "$NODE" -- bash -c "echo '$ND_IP ${ND}.local' | sudo tee -a /etc/hosts"
    fi
  done

  echo "Updating /etc/hosts on $NODE completed."
  multipass exec "$NODE" -- sudo systemctl restart systemd-resolved
done

# Step 8: Add nodes to the cluster
echo "🌟 Adding worker nodes to the cluster..."
for NODE in "${WORKER_NODES[@]}"; do
  JOIN_CMD=$(multipass exec "$MASTER_NODE" -- microk8s add-node | grep "microk8s join" | grep "\-\-worker")
  echo "🔗 Joining $NODE to the cluster..."
  multipass exec "$NODE" -- $JOIN_CMD && sleep 10 && sync
done

# Step : install nfs server on the host
if [ -z "$(ps ax | grep "\/usr\/sbin\/nfsd" | grep -v grep)" ]; then
  echo "📦 Installing NFS server on the host machine..."
  sudo apt-get update && apt-get upgrade -y
  sudo apt-get install -y nfs-kernel-server watchdog open-iscsi

  sync
  sudo mkdir -p /srv/nfs/uk8s
  sudo chown nobody:nogroup /srv/nfs/uk8s
  sudo chmod 777 /srv/nfs/uk8s

  sudo mv /etc/exports /etc/exports.bak
  echo "/srv/nfs/uk8s ${UK8S_NETCLS}.0/24(rw,sync,no_subtree_check)" | sudo tee /etc/exports
  sudo systemctl restart nfs-kernel-server

  echo "Installing CSI driver for NFS in the cluster..."
  multipass exec "$MASTER_NODE" -- microk8s enable helm3
  multipass exec "$MASTER_NODE" -- microk8s helm3 repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
  multipass exec "$MASTER_NODE" -- microk8s helm3 repo update
  sync

  multipass exec "$MASTER_NODE" -- microk8s helm3 install csi-driver-nfs csi-driver-nfs/csi-driver-nfs \
    --namespace kube-system \
    --set kubeletDir=/var/snap/microk8s/common/var/lib/kubelet

  multipass exec "$MASTER_NODE" -- microk8s kubectl wait pod --selector app.kubernetes.io/name=csi-driver-nfs --for condition=ready --namespace kube-system
  sync && multipass exec "$MASTER_NODE" -- microk8s kubectl get csidrivers
fi

# Step 5: Setup addons and enable services on the master node
if is_microk8s_addon_enabled "metallb"; then
  echo "✅ Metallb addon is already enabled."
else
  echo "🔧 Setting up loadbalancer (metallb) in the cluster..."
  multipass exec "$MASTER_NODE" -- microk8s enable dns
  multipass exec "$MASTER_NODE" -- microk8s enable ingress
  multipass exec "$MASTER_NODE" -- microk8s enable metallb:${UK8S_NETCLS}.151-${UK8S_NETCLS}.250
  multipass exec "$MASTER_NODE" -- microk8s status --wait-ready
fi

# Step 6: Get kube config from master
echo "📄 Fetching kubeconfig..."
mkdir -p ~/.kube
touch ~/.kube/config
cp ~/.kube/config ~/.kube/config.bak
multipass exec "$MASTER_NODE" -- microk8s config >~/.kube/uk8s-config
KUBECONFIG=~/.kube/uk8s-config:~/.kube/config kubectl config view --flatten >~/.kube/config && rm -f ~/.kube/uk8s-config ~/.kube/config.bak
chmod 600 ~/.kube/config
kubectl config use-context "$KUBECTL_CTX"

# Step 7: Check and add uk8s-master.local entry in /etc/hosts on the host machine
if grep -q "[[:space:]]uk8s-master\.local" /etc/hosts; then
  echo "Updating existing uk8s-master.local entry with IP $MASTER_IP"
  sudo sed -i "/[[:space:]]uk8s-master\.local/ s/^[^[:space:]]*/$MASTER_IP/" /etc/hosts
else
  echo "Adding new uk8s-master.local entry with IP $MASTER_IP"
  echo "$MASTER_IP uk8s-master.local" | sudo tee -a /etc/hosts
fi

echo "✅ Cluster is ready!"
kubectl get nodes -o wide
