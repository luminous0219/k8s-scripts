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

### MetalLB Load Balancer Setup (Optional)

**Install MetalLB for LoadBalancer services:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/luminous0219/k8s-scripts/main/install-metallb.sh)"
```

> **Note:** MetalLB provides LoadBalancer functionality for bare metal Kubernetes clusters. Run this after your cluster is set up.

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
- **MetalLB Support** - Optional LoadBalancer functionality for bare metal clusters

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

## 🌐 MetalLB Load Balancer Setup

MetalLB provides LoadBalancer functionality for bare metal Kubernetes clusters, allowing you to expose services with external IPs.

### Why MetalLB?

In cloud environments, LoadBalancer services automatically get external IPs. On bare metal, you need MetalLB to:
- Assign external IPs to LoadBalancer services
- Make services accessible from outside the cluster
- Enable true load balancing for your applications

### Installation

**One-liner installation:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/luminous0219/k8s-scripts/main/install-metallb.sh)"
```

### What the MetalLB script does:

1. **Detects your network** - Automatically identifies your cluster's network range
2. **Interactive configuration** - Prompts you to specify IP address range
3. **Installs MetalLB v0.14.9** - Latest stable version
4. **Configures IP pool** - Sets up address pool and L2 advertisement
5. **Creates test service** - Verifies functionality with nginx deployment
6. **Validates setup** - Ensures external IP assignment works

### IP Range Configuration

The script will ask you to specify an IP range in one of these formats:

**CIDR Notation:**
```
192.168.1.240/28    # Provides 16 IPs (.240-.255)
192.168.1.200/29    # Provides 8 IPs (.200-.207)
```

**Range Notation:**
```
192.168.1.240-192.168.1.250    # Provides 11 IPs
192.168.1.100-192.168.1.110    # Provides 11 IPs
```

### Important Considerations:

- **Available IPs**: Choose IPs not used by DHCP or static assignments
- **Network subnet**: IPs must be in your network's subnet
- **Firewall**: Ensure firewall allows traffic to assigned IPs
- **Router**: IPs should be routable within your network

### Usage Examples:

**Expose a deployment:**
```bash
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --type=LoadBalancer --port=80
kubectl get svc nginx  # Check assigned external IP
```

**Access your service:**
```bash
# Get the external IP
EXTERNAL_IP=$(kubectl get svc nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl http://$EXTERNAL_IP
```

### Troubleshooting MetalLB:

**Check MetalLB status:**
```bash
kubectl get pods -n metallb-system
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system
```

**Service stuck in pending:**
```bash
kubectl describe svc <service-name>
kubectl logs -n metallb-system -l app=metallb
```