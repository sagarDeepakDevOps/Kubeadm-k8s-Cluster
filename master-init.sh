#!/bin/bash

set -euo pipefail

##############################
# CONFIGURABLE VARIABLES
##############################

MASTER_IP="192.168.56.10"
POD_CIDR="192.168.0.0/16"
CNI="calico"
JOIN_CMD_FILE="~/kubeadm-join.sh"
LOG_FILE="/var/log/kubeadm-master-init.log"

##############################
# LOGGING
##############################

sudo touch "$LOG_FILE"
sudo chown "$(id -u):$(id -g)" "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "===== KUBEADM MASTER INIT STARTED ====="
echo "Node        : $(hostname)"
echo "K8S VERSION : v${K8S_VERSION}"
echo "Time        : $(date)"

##############################
# SAFETY CHECKS
##############################

if [ -f /etc/kubernetes/admin.conf ]; then
  echo "❌ Kubernetes already initialized on this node"
  exit 0
fi

##############################
# KUBEADM INIT
##############################

echo "[1/6] Initializing control plane..."

sudo kubeadm init \
  --apiserver-advertise-address="${MASTER_IP}" \
  --pod-network-cidr="${POD_CIDR}"

##############################
# KUBECTL CONFIG
##############################

echo "[2/6] Configuring kubectl..."

mkdir -p "$HOME/.kube"
sudo cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"

##############################
# INSTALL CNI
##############################

echo "[3/6] Installing CNI (${CNI})..."

if [ "$CNI" = "calico" ]; then
  kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml
else
  echo "Unsupported CNI"
  exit 1
fi

##############################
# WAIT FOR CONTROL PLANE
##############################

echo "[4/6] Waiting for control plane to be Ready..."

kubectl wait --for=condition=Ready node "$(hostname)" --timeout=300s

##############################
# GENERATE JOIN COMMAND
##############################

echo "[5/6] Generating worker join command..."

JOIN_CMD=$(sudo kubeadm token create --print-join-command)

echo "#!/bin/bash" | tee "$JOIN_CMD_FILE"
echo "sudo $JOIN_CMD" | tee -a "$JOIN_CMD_FILE"

##############################
# DONE
##############################

echo "[6/6] Master initialization completed"

echo ""
echo "JOIN COMMAND SAVED AT:"
echo "  $JOIN_CMD_FILE"
echo ""
echo "Run this file on ALL worker nodes."

echo "===== MASTER SETUP COMPLETE ====="
