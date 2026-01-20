#!/bin/bash

set -euo pipefail

##############################
# COLORS & FORMATTING
##############################
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
PURPLE="\033[0;35m"
CYAN="\033[0;36m"
BOLD="\033[1m"
RESET="\033[0m"

info()    { echo -e "${BLUE}${BOLD}[INFO]${RESET} $1"; }
success() { echo -e "${GREEN}${BOLD}[SUCCESS]${RESET} $1"; }
warn()    { echo -e "${YELLOW}${BOLD}[WARN]${RESET} $1"; }
section() {
  echo -e "\n${PURPLE}${BOLD}================================================"
  echo -e "$1"
  echo -e "================================================${RESET}\n"
}

##############################
# CONFIG
##############################
K8S_VERSION="1.33"
LOG_FILE="/var/log/kubeadm-prereq.log"

##############################
# LOGGING
##############################
sudo touch "$LOG_FILE"
sudo chown "$(id -u):$(id -g)" "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

section "KUBEADM PREREQUISITE SETUP STARTED"

info "Node        : $(hostname)"
info "K8S Version : v${K8S_VERSION}"
info "Timestamp  : $(date)"

##############################
# 1. DISABLE SWAP
##############################
section "STEP 1/8 - DISABLE SWAP"

info "Disabling swap..."
sudo swapoff -a || warn "Swap already disabled"
sudo sed -i '/ swap / s/^/#/' /etc/fstab
success "Swap disabled successfully"

##############################
# 2. KERNEL MODULES
##############################
section "STEP 2/8 - LOAD KERNEL MODULES"

info "Loading overlay & br_netfilter modules..."

sudo tee /etc/modules-load.d/k8s.conf >/dev/null <<EOF
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

success "Kernel modules loaded"

##############################
# 3. SYSCTL SETTINGS
##############################
section "STEP 3/8 - APPLY SYSCTL SETTINGS"

info "Configuring Kubernetes networking sysctl parameters..."

sudo tee /etc/sysctl.d/k8s.conf >/dev/null <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
success "Sysctl parameters applied"

##############################
# 4. INSTALL CONTAINERD $ PRE-REQ
##############################
section "STEP 4/8 - INSTALL CONTAINERD"

info "Installing containerd and dependencies..."

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
  info "Generating default containerd config..."
  sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
fi

info "Configuring containerd to use systemd cgroup..."

sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' \
  /etc/containerd/config.toml

sudo systemctl restart containerd
sudo systemctl enable containerd

success "containerd installed and configured"

##############################
# 5. INSTALL KUBERNETES BINARIES
##############################
section "STEP 5/8 - INSTALL KUBERNETES COMPONENTS"

info "Adding Kubernetes repository..."

sudo mkdir -p /etc/apt/keyrings

if [ ! -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg ]; then
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key \
    | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
fi

sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null <<EOF
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /
EOF

info "Installing kubelet, kubeadm, kubectl..."

sudo apt-get update -y
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

success "Kubernetes binaries installed and pinned"

##############################
# 6. ENABLE SERVICES
##############################
section "STEP 6/8 - ENABLE SERVICES"

info "Enabling kubelet service..."
sudo systemctl enable kubelet
success "kubelet enabled"

##############################
# 7. VALIDATION
##############################
section "STEP 7/8 - VALIDATION CHECKS"

info "containerd version:"
containerd --version || warn "containerd not responding"

info "kubeadm version:"
kubeadm version || warn "kubeadm not responding"

info "kubelet status:"
sudo systemctl is-active kubelet || warn "kubelet not active yet"

##############################
# DONE
##############################
section "SETUP COMPLETED SUCCESSFULLY"

success "All Kubernetes prerequisites installed"
info "Log file saved at: $LOG_FILE"

echo -e "${CYAN}${BOLD}NEXT STEPS:${RESET}"
echo -e "  ${GREEN}MASTER${RESET} : kubeadm init ..."
echo -e "  ${GREEN}WORKER${RESET} : kubeadm join ..."
echo
