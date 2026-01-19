This assumes your **Vagrant/EC2 setup**:

* 1 master: `k8s-master `
* 2 workers: `k8s-worker1`, `k8s-worker2`
* OS: Ubuntu 20.04 / 22.04
* Runtime: **containerd** (Docker is deprecated for kubeadm)

---

# 🧱 HIGH-LEVEL FLOW (MEMORIZE THIS)

```
OS prep (all nodes)
 → container runtime
 → kubeadm/kubelet/kubectl
 → master init
 → CNI install
 → join workers
 → validate cluster
```

If you understand this flow, **you understand kubeadm**.

---

# 🔹 STEP 0 – Switch to Root User

```bash
sudo su 
```


---

# 🔹 STEP 1 – SYSTEM PRE-REQS (ALL NODES)

### 1. Disable swap (MANDATORY)

```bash
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab
```

Verify:

```bash
free -h
```

If swap exists → kubeadm **WILL FAIL**.

---

### 2. Load kernel modules

```bash
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter
```

---

### 3. Sysctl settings (networking)

```bash
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system
```

Verify:

```bash
sysctl net.ipv4.ip_forward
```

---

# 🔹 STEP 2 – INSTALL CONTAINERD (ALL NODES)

### 1. Install dependencies

```bash
apt update
apt install -y apt-transport-https ca-certificates curl gnupg lsb-release
```

---

### 2. Install containerd

```bash
apt install -y containerd
```

---

### 3. Configure containerd **(VERY IMPORTANT)**

```bash
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
```

Edit config:

```bash
vi /etc/containerd/config.toml
```

Find:

```toml
SystemdCgroup = false
```

Change to:

```toml
SystemdCgroup = true
```

---

### 4. Restart containerd

```bash
systemctl restart containerd
systemctl enable containerd
```

Verify:

```bash
crictl info
```

---

# 🔹 STEP 3 – INSTALL KUBERNETES BINARIES (ALL NODES)

### 1. Add Kubernetes repo

```bash
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key \
| gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
```

```bash
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /" \
| tee /etc/apt/sources.list.d/kubernetes.list
```

---

### 2. Install tools

```bash
apt update
apt install -y kubelet kubeadm kubectl
```

---

### 3. Hold versions (PRODUCTION RULE)

```bash
apt-mark hold kubelet kubeadm kubectl
```

Verify:

```bash
kubeadm version
```

---

# 🔹 STEP 4 – INITIALIZE CONTROL PLANE (MASTER ONLY)

### Run ONLY on `k8s-master`

```bash
#use master ip addr
kubeadm init \
  --apiserver-advertise-address=192.168.56.10 \
  --pod-network-cidr=192.168.0.0/16

```

✔ `--pod-network-cidr` depends on CNI (Calico uses `/16`)

---

### SAVE THIS OUTPUT ❗

You’ll see:

```bash
kubeadm join ... --token ... --discovery-token-ca-cert-hash ...
```
---

### Configure kubectl (MASTER)

```bash
mkdir -p $HOME/.kube
cp /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config
```

Test:

```bash
kubectl get nodes
```

Master will show:

```
NotReady
```

✅ NORMAL (CNI not installed yet)

---

# 🔹 STEP 5 – INSTALL CNI (NETWORK PLUGIN)

### Calico (MOST COMMON & INTERVIEW-SAFE)

```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml
```

Wait:

```bash
kubectl get pods -n kube-system
```

When Calico pods are **Running**, master becomes:

```bash
kubectl get nodes
```

```
k8s-master   Ready
```

---

# 🔹 STEP 6 – JOIN WORKER NODES

Run the **join command** (from init output) on:

* `k8s-worker1`
* `k8s-worker2`

Example:

```bash
kubeadm join 192.168.56.10:6443 \
 --token abcdef.123456 \
 --discovery-token-ca-cert-hash sha256:xxxx
```

---

### Validate from MASTER

```bash
kubectl get nodes -o wide
```

Expected:

```
k8s-master    Ready
k8s-worker1  Ready
k8s-worker2  Ready
```

🎉 Cluster is UP.

---

# 🔹 STEP 7 – POST-INSTALL HARDENING (SENIOR LEVEL)

### Enable kubelet at boot

```bash
systemctl enable kubelet
```

---

### Test scheduling

```bash
kubectl run nginx --image=nginx
kubectl get pods -o wide
```

---

### Optional: Remove control-plane taint

```bash
kubectl taint nodes k8s-master node-role.kubernetes.io/control-plane-
```

---

# 🔹 STEP 8 – CLUSTER HEALTH CHECKS 

```bash
kubectl get componentstatuses
kubectl cluster-info
kubectl get events -A
kubectl get pods -A
```

---

# 🧠 COMMON FAILURES 

| Issue                        | Cause                      |
| ---------------------------- | -------------------------- |
| kubeadm init fails           | swap enabled               |
| Nodes NotReady               | CNI missing                |
| Pods stuck ContainerCreating | containerd cgroup mismatch |
| kubelet crashloop            | wrong CRI                  |
| API unreachable              | wrong advertise address    |

---


