#!/bin/bash

set -euo pipefail

##############################
# CONFIGURABLE VARIABLES
##############################

K8S_VERSION="1.33"
LOG_FILE="/var/log/kubeadm-prereq.log"

##############################
# LOGGING SETUP
##############################

sudo touch "$LOG_FILE"
sudo chown "$(id -u):$(id -g)" "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "===== KUBEADM PREREQUISITE SETUP STARTED ====="
echo "Node      : $(hostname)"
echo "K8S VER   : v${K8S_VERSION}"
echo "Timestamp : $(date)"

##############################
# 1. DISABLE SWAP
##############################

echo "[1/8] Disabling swap..."
sudo swapoff -a || true
sudo sed -i '/ swap / s/^/#/' /etc/fstab

##############################
# 2. KERNEL MODULES
##############################

echo "[2/8] Loading kernel modules..."

sudo tee /etc/modules-load.d/k8s.conf >/dev/null <<EOF
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

##############################
# 3. SYSCTL SETTINGS
##############################

echo "[3/8] Applying sysctl parameters..."

sudo tee /etc/sysctl.d/k8s.conf >/dev/null <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

##############################
# 4. INSTALL CONTAINERD
##############################

echo "[4/8] Installing containerd..."

sudo apt-get update -y
sudo apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  apt-transport-https \
  containerd

sudo mkdir -p /etc/containerd

if [ ! -f /etc/containerd/config.toml ]; then
  sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
fi

echo "[5/8] Configuring containerd (systemd cgroup)..."

sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' \
  /etc/containerd/config.toml

sudo systemctl restart containerd
sudo systemctl enable containerd

##############################
# 5. INSTALL KUBERNETES BINARIES
##############################

echo "[6/8] Installing Kubernetes components..."

sudo mkdir -p /etc/apt/keyrings

if [ ! -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg ]; then
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key \
    | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
fi

sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null <<EOF
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /
EOF

sudo apt-get update -y
sudo apt-get install -y kubelet kubeadm kubectl

sudo apt-mark hold kubelet kubeadm kubectl

##############################
# 6. ENABLE SERVICES
##############################

echo "[7/8] Enabling kubelet..."
sudo systemctl enable kubelet

##############################
# 7. VALIDATION
##############################

echo "[8/8] Validation checks..."

echo "containerd:"
containerd --version || true

echo "kubeadm:"
kubeadm version || true

echo "kubelet status:"
sudo systemctl is-active kubelet || true

##############################
# DONE
##############################

echo "===== SETUP COMPLETED SUCCESSFULLY ====="
echo "Log file: $LOG_FILE"
echo ""
echo "NEXT STEPS:"
echo "  MASTER : kubeadm init ..."
echo "  WORKER : kubeadm join ..."
