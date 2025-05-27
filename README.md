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

### ArgoCD GitOps Setup (Optional)

**Install ArgoCD with MetalLB LoadBalancer:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/luminous0219/k8s-scripts/main/install-argocd.sh)"
```

> **Note:** ArgoCD provides GitOps functionality for continuous deployment. Requires MetalLB to be installed first.

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
- **ArgoCD Integration** - Optional GitOps functionality with MetalLB LoadBalancer

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

## 🚀 ArgoCD GitOps Setup

ArgoCD provides GitOps functionality for continuous deployment, allowing you to manage applications declaratively through Git repositories.

### Why ArgoCD?

ArgoCD enables GitOps workflows by:
- Automatically syncing applications from Git repositories
- Providing a web UI for application management
- Supporting multi-cluster deployments
- Offering rollback and history tracking
- Implementing security and RBAC controls

### Prerequisites

ArgoCD requires MetalLB to be installed first for LoadBalancer functionality:
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/luminous0219/k8s-scripts/main/install-metallb.sh)"
```

### Installation

**One-liner installation:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/luminous0219/k8s-scripts/main/install-argocd.sh)"
```

### What the ArgoCD script does:

1. **Checks prerequisites** - Verifies MetalLB is installed and running
2. **Detects IP pools** - Shows available MetalLB IP address ranges
3. **Interactive IP selection** - Prompts you to choose an IP for ArgoCD
4. **Installs ArgoCD** - Deploys latest stable version
5. **Configures LoadBalancer** - Exposes ArgoCD via MetalLB with your chosen IP
6. **Retrieves admin password** - Gets the initial admin password
7. **Optional sample app** - Creates a guestbook application for testing

### IP Address Selection

The script will show your MetalLB pools and help you choose an available IP:

```
Available MetalLB IP pools:
  • 192.168.31.200/29

Examples of valid IPs (choose one that's not already in use):
  From 192.168.31.200/29: 192.168.31.201, 192.168.31.202, 192.168.31.203
```

### Access ArgoCD

After installation, you can access ArgoCD at:
- **URL**: `https://YOUR_CHOSEN_IP`
- **Username**: `admin`
- **Password**: Displayed during installation or retrieve with:
  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
  ```

### Browser Security Warning

ArgoCD uses a self-signed certificate, so your browser will show a security warning:
1. Click **"Advanced"**
2. Click **"Proceed to [IP address]"**
3. Login with admin credentials

### Sample Application

The script can create a sample guestbook application to demonstrate ArgoCD:
1. Login to ArgoCD UI
2. Find the "guestbook" application
3. Click **"Sync"** to deploy it
4. Monitor the deployment progress

### Creating Your Own Applications

**Via ArgoCD UI:**
1. Click **"+ New App"**
2. Fill in application details:
   - **Application Name**: Your app name
   - **Project**: default
   - **Repository URL**: Your Git repository
   - **Path**: Path to Kubernetes manifests
   - **Cluster URL**: https://kubernetes.default.svc
   - **Namespace**: Target namespace
3. Click **"Create"**
4. Click **"Sync"** to deploy

**Via kubectl:**
```bash
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-username/your-repo.git
    targetRevision: HEAD
    path: k8s-manifests
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
EOF
```

### Useful Commands

**Check ArgoCD status:**
```bash
kubectl get pods -n argocd
kubectl get svc -n argocd
```

**Get admin password:**
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

**View applications:**
```bash
kubectl get applications -n argocd
```

**ArgoCD CLI (optional):**
```bash
# Install ArgoCD CLI
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd

# Login via CLI
argocd login YOUR_ARGOCD_IP --username admin --password YOUR_PASSWORD --insecure
```

### Troubleshooting ArgoCD

**Can't access UI:**
```bash
# Check LoadBalancer service
kubectl get svc argocd-server-loadbalancer -n argocd

# Check if IP is assigned
kubectl describe svc argocd-server-loadbalancer -n argocd
```

**Application sync issues:**
```bash
# Check application status
kubectl describe application YOUR_APP_NAME -n argocd

# View ArgoCD server logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server
```

**Reset admin password:**
```bash
# Delete the secret to regenerate
kubectl delete secret argocd-initial-admin-secret -n argocd
kubectl rollout restart deployment argocd-server -n argocd
```