# Kubernetes 1.33 Automated Installation Scripts

This repository contains automated installation scripts for setting up a Kubernetes 1.33 cluster on Ubuntu/Debian systems. The scripts are designed to be production-ready with comprehensive error handling and logging.

## 🚀 Quick Start (One-Liner Installation)

### Multi-Node Cluster Setup

**Master Node Installation:**
```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/luminous0219/k8s-scripts/main/install-k8s-master.sh)"
```

**Worker Node Installation:**
```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/luminous0219/k8s-scripts/main/install-k8s-worker.sh)"
```

### Single-Node Cluster Setup (Development/Testing)

**Complete cluster on one machine:**
```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/luminous0219/k8s-scripts/main/install-k8s-single-node.sh)"
```

### 🔒 Security Note for One-Liner Installation

While the one-liner installation is convenient, for production environments consider:

1. **Review the script first**: Download and inspect before running
   ```bash
   curl -fsSL https://raw.githubusercontent.com/luminous0219/k8s-scripts/main/install-k8s-master.sh
   ```

2. **Use specific commit hash** for reproducible installations:
   ```bash
   sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/luminous0219/k8s-scripts/COMMIT_HASH/install-k8s-master.sh)"
   ```

3. **Verify script integrity** using checksums (if provided)

## 🚀 Features

- **Latest Kubernetes 1.33.1** - Uses the most recent stable release
- **Modern Package Repository** - Uses the new `pkgs.k8s.io` repository
- **Automated Setup** - Complete cluster setup with minimal user intervention
- **Production Ready** - Includes proper security configurations and best practices
- **Comprehensive Logging** - Detailed output with color-coded messages
- **Error Handling** - Robust validation and error recovery
- **CNI Included** - Flannel CNI automatically configured
- **One-Liner Installation** - No need to clone repository

## 🛠️ Installation

### Method 1: One-Liner Installation (Recommended)

**Install Master Node:**
```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/luminous0219/k8s-scripts/main/install-k8s-master.sh)"
```

**Install Worker Nodes:**
```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/luminous0219/k8s-scripts/main/install-k8s-worker.sh)"
```

### Method 2: Download and Execute

If you prefer to download the scripts first:

```bash
# Download master script
curl -fsSL https://raw.githubusercontent.com/luminous0219/k8s-scripts/main/install-k8s-master.sh -o install-k8s-master.sh
chmod +x install-k8s-master.sh
sudo ./install-k8s-master.sh

# Download worker script
curl -fsSL https://raw.githubusercontent.com/luminous0219/k8s-scripts/main/install-k8s-worker.sh -o install-k8s-worker.sh
chmod +x install-k8s-worker.sh
sudo ./install-k8s-worker.sh
```

### Method 3: Git Clone (Traditional)

```bash
# Clone this repository
git clone https://github.com/luminous0219/k8s-scripts.git
cd k8s-scripts

# Make scripts executable
chmod +x install-k8s-master.sh
chmod +x install-k8s-worker.sh

# Run scripts
sudo ./install-k8s-master.sh
sudo ./install-k8s-worker.sh
```

### Installation Process

**Master Node Setup:**
1. Updates system packages
2. Installs and configures containerd
3. Adds Kubernetes 1.33 repository
4. Installs kubeadm, kubelet, and kubectl
5. Initializes the Kubernetes cluster
6. Installs Flannel CNI
7. Generates join command for worker nodes

**Worker Node Setup:**
- The script will prepare the system (same as master)
- You'll be prompted to enter the join command from the master node
- Copy and paste the complete join command when prompted

**Expected Output:**
- The script will display progress with timestamps
- At the end, you'll see cluster information and a join command
- The join command is saved to `/tmp/kubeadm-join-command.txt`

### Verify Installation

On the master node, verify your cluster:

```bash
# Check node status
kubectl get nodes

# Check all pods
kubectl get pods -A

# Check cluster info
kubectl cluster-info
```

## 🎯 Complete Example Workflow

Here's how to set up a complete 2-node cluster using the one-liner approach:

### Step 1: Set up Master Node
On your master node (e.g., `192.168.1.10`):
```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/luminous0219/k8s-scripts/main/install-k8s-master.sh)"
```

### Step 2: Get Join Command
After master installation completes, copy the join command from the output or from:
```bash
cat /tmp/kubeadm-join-command.txt
```

### Step 3: Set up Worker Node
On your worker node (e.g., `192.168.1.11`):
```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/luminous0219/k8s-scripts/main/install-k8s-worker.sh)"
```
When prompted, paste the join command from Step 2.

### Step 4: Verify Cluster
Back on the master node:
```bash
kubectl get nodes
# Should show both master and worker nodes as Ready
```

**That's it! Your Kubernetes 1.33 cluster is ready! 🎉**