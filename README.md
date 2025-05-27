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

### NVIDIA GPU Drivers Setup (Optional)

**Install NVIDIA drivers for GPU workloads:**
```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/luminous0219/k8s-scripts/main/install-nvidia-drivers.sh)"
```

> **Note:** NVIDIA drivers enable GPU workloads in Kubernetes. Run this on worker nodes with NVIDIA GPUs after cluster setup.

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

### Autostart Verification (Recommended)

**Verify and fix autostart for all services:**
```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/luminous0219/k8s-scripts/main/verify-autostart.sh)"
```

> **Note:** Ensures all Kubernetes services, MetalLB, ArgoCD, and NVIDIA components start automatically after system reboot.

### Fix Startup Issues (Emergency)

**If Kubernetes fails to start after reboot:**
```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/luminous0219/k8s-scripts/main/fix-k8s-startup.sh)"
```

> **Note:** Run this immediately when you get "connection refused" errors after reboot. Diagnoses and fixes common startup issues.

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
- **NVIDIA GPU Support** - Optional GPU drivers and Kubernetes device plugin
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

## 🎮 NVIDIA GPU Drivers Setup

NVIDIA GPU drivers enable GPU-accelerated workloads in Kubernetes, allowing you to run machine learning, AI, and high-performance computing applications.

### Why NVIDIA GPU Support?

GPU support in Kubernetes enables:
- **Machine Learning workloads** - Train and run ML models with GPU acceleration
- **AI applications** - Deploy AI inference services with high performance
- **Scientific computing** - Run CUDA-based applications and simulations
- **Video processing** - Hardware-accelerated video encoding/decoding
- **Cryptocurrency mining** - GPU-based mining operations

### Prerequisites

NVIDIA GPU drivers should be installed on worker nodes that have NVIDIA GPUs:
- **Physical NVIDIA GPU** - System must have NVIDIA graphics card
- **Kubernetes cluster** - Worker node should be part of a Kubernetes cluster
- **Ubuntu/Debian** - Compatible with Ubuntu 20.04+ and Debian 11+

### Installation

**One-liner installation:**
```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/luminous0219/k8s-scripts/main/install-nvidia-drivers.sh)"
```

### What the NVIDIA script does:

1. **GPU Detection** - Automatically detects NVIDIA GPUs using `lspci`
2. **Driver Installation** - Installs latest stable NVIDIA drivers (550 series)
3. **Container Toolkit** - Installs NVIDIA Container Toolkit for container support
4. **Containerd Configuration** - Configures containerd runtime for GPU access
5. **Device Plugin** - Deploys NVIDIA Device Plugin to Kubernetes
6. **Verification** - Tests GPU functionality and Kubernetes integration
7. **Optional test workload** - Creates sample GPU pod for validation

### Installation Process

**What gets installed:**
- **NVIDIA Driver 550** - Latest stable driver series
- **NVIDIA Container Toolkit** - Enables GPU access in containers
- **NVIDIA Device Plugin** - Exposes GPUs as Kubernetes resources
- **Containerd configuration** - Runtime support for GPU containers

**Expected behavior:**
- Script detects NVIDIA GPUs automatically
- Cleans up any existing NVIDIA installations
- Installs drivers and container runtime support
- Configures Kubernetes for GPU scheduling
- May require system reboot to complete installation

### Verify Installation

After installation (and potential reboot), verify GPU functionality:

```bash
# Check NVIDIA driver
nvidia-smi

# Check GPU nodes in Kubernetes
kubectl describe nodes | grep nvidia.com/gpu

# Check device plugin pods
kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds

# Test GPU container
docker run --rm --gpus all nvidia/cuda:12.2-runtime-ubuntu20.04 nvidia-smi
```

### Usage Examples

**Deploy GPU workload:**
```bash
# Create a simple GPU test pod
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test
spec:
  restartPolicy: Never
  containers:
  - name: gpu-test
    image: nvidia/cuda:12.2-runtime-ubuntu20.04
    command: ["nvidia-smi"]
    resources:
      limits:
        nvidia.com/gpu: 1
EOF

# Check the results
kubectl logs gpu-test
```

**Machine Learning example:**
```bash
# Deploy TensorFlow with GPU
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tensorflow-gpu
spec:
  replicas: 1
  selector:
    matchLabels:
      app: tensorflow-gpu
  template:
    metadata:
      labels:
        app: tensorflow-gpu
    spec:
      containers:
      - name: tensorflow
        image: tensorflow/tensorflow:latest-gpu
        resources:
          limits:
            nvidia.com/gpu: 1
        command: ["python", "-c"]
        args: ["import tensorflow as tf; print('GPUs:', tf.config.list_physical_devices('GPU'))"]
EOF
```

**PyTorch example:**
```bash
# Deploy PyTorch with GPU
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: pytorch-gpu
spec:
  restartPolicy: Never
  containers:
  - name: pytorch
    image: pytorch/pytorch:latest
    resources:
      limits:
        nvidia.com/gpu: 1
    command: ["python", "-c"]
    args: ["import torch; print('CUDA available:', torch.cuda.is_available()); print('GPU count:', torch.cuda.device_count())"]
EOF
```

### GPU Resource Management

**Request specific GPU count:**
```yaml
resources:
  limits:
    nvidia.com/gpu: 2  # Request 2 GPUs
```

**GPU node selection:**
```yaml
nodeSelector:
  accelerator: nvidia-tesla-k80  # Select specific GPU type
```

**GPU sharing (if supported):**
```yaml
resources:
  limits:
    nvidia.com/gpu: 0.5  # Share GPU (requires MIG or similar)
```

### Monitoring GPU Usage

**Check GPU utilization:**
```bash
# On the node with GPUs
nvidia-smi

# Continuous monitoring
watch -n 1 nvidia-smi
```

**Kubernetes GPU metrics:**
```bash
# Check GPU capacity and allocation
kubectl describe nodes | grep -A 5 "Capacity:" | grep nvidia.com/gpu
kubectl describe nodes | grep -A 5 "Allocatable:" | grep nvidia.com/gpu
```

### Troubleshooting NVIDIA

**Driver issues:**
```bash
# Check driver installation
nvidia-smi
lsmod | grep nvidia

# Check driver version
cat /proc/driver/nvidia/version
```

**Container runtime issues:**
```bash
# Test container access
docker run --rm --gpus all nvidia/cuda:12.2-runtime-ubuntu20.04 nvidia-smi

# Check containerd configuration
grep nvidia /etc/containerd/config.toml
```

**Kubernetes device plugin issues:**
```bash
# Check device plugin status
kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds
kubectl logs -n kube-system -l name=nvidia-device-plugin-ds

# Check node GPU resources
kubectl get nodes -o yaml | grep nvidia.com/gpu
```

**Pod scheduling issues:**
```bash
# Check pod events
kubectl describe pod YOUR_GPU_POD

# Check node GPU availability
kubectl describe nodes | grep nvidia.com/gpu
```

**Common solutions:**
- **Reboot required**: NVIDIA driver installation often requires reboot
- **Containerd restart**: `sudo systemctl restart containerd`
- **Device plugin restart**: `kubectl delete pods -n kube-system -l name=nvidia-device-plugin-ds`
- **Check GPU compatibility**: Ensure GPU is supported by driver version

### Important Notes

**System requirements:**
- **NVIDIA GPU**: Physical NVIDIA graphics card required
- **Kernel headers**: Must match running kernel version
- **Secure Boot**: May need to be disabled for driver installation
- **Power management**: Ensure adequate power supply for GPU

**Best practices:**
- **Resource limits**: Always specify GPU resource limits
- **Image compatibility**: Use NVIDIA-compatible container images
- **Monitoring**: Monitor GPU utilization and temperature
- **Updates**: Keep drivers updated for security and performance

**Supported workloads:**
- Machine Learning (TensorFlow, PyTorch, etc.)
- AI inference services
- CUDA applications
- Video processing
- Scientific computing
- Cryptocurrency mining

## 🔄 Autostart Verification

Ensuring all Kubernetes services start automatically after system reboot is critical for production environments. This section covers autostart verification and configuration.

### Why Autostart Verification?

System reboots can cause issues if services don't start automatically:
- **Kubernetes cluster becomes unavailable** - Core services fail to start
- **Applications don't restart** - Pods remain in pending state
- **Load balancers fail** - MetalLB services become inaccessible
- **GitOps stops working** - ArgoCD becomes unavailable
- **GPU workloads fail** - NVIDIA device plugin doesn't start

### Autostart Verification Script

**One-liner verification:**
```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/luminous0219/k8s-scripts/main/verify-autostart.sh)"
```

### What the Autostart Script Does

1. **Verifies Core Services** - Checks kubelet and containerd autostart
2. **Creates Startup Services** - Adds custom systemd services for reliability
3. **Checks Kubernetes Apps** - Verifies MetalLB, ArgoCD, NVIDIA plugin status
4. **Creates Recovery Scripts** - Adds comprehensive startup check scripts
5. **Enables All Services** - Ensures everything starts automatically
6. **Provides Status Report** - Shows current service status

### Services Configured for Autostart

**Core Kubernetes Services:**
- `containerd` - Container runtime
- `kubelet` - Kubernetes node agent
- `kubernetes-startup` - Custom startup service
- `k8s-startup-check` - Comprehensive check service

**Kubernetes Applications (Pods):**
- All system pods (kube-system namespace)
- MetalLB load balancer (if installed)
- ArgoCD GitOps platform (if installed)
- NVIDIA device plugin (if installed)
- All user applications and deployments

### Manual Verification Commands

**Check service status:**
```bash
# Check if services are enabled for autostart
sudo systemctl is-enabled kubelet containerd

# Check if services are currently running
sudo systemctl is-active kubelet containerd

# Check all Kubernetes services
sudo systemctl status kubelet containerd kubernetes-startup k8s-startup-check
```

**Check Kubernetes cluster:**
```bash
# Check cluster accessibility
kubectl cluster-info

# Check node status
kubectl get nodes

# Check all pods
kubectl get pods --all-namespaces

# Check specific applications
kubectl get pods -n metallb-system  # MetalLB
kubectl get pods -n argocd          # ArgoCD
kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds  # NVIDIA
```

### Testing Autostart

**Test with system reboot:**
```bash
# Reboot the system
sudo reboot

# After reboot, wait 2-3 minutes, then check:
kubectl get nodes
kubectl get pods --all-namespaces
```

**Expected behavior after reboot:**
1. **System boots normally** (1-2 minutes)
2. **Core services start** - containerd and kubelet start automatically
3. **Kubernetes cluster becomes ready** - nodes show as Ready
4. **All pods restart** - system and application pods start running
5. **Applications become accessible** - MetalLB assigns IPs, ArgoCD UI available

### Troubleshooting Autostart Issues

**Services not starting:**
```bash
# Check service logs
sudo journalctl -u kubelet -f
sudo journalctl -u containerd -f
sudo journalctl -u kubernetes-startup -f

# Manually start services
sudo systemctl start containerd
sudo systemctl start kubelet

# Check service dependencies
sudo systemctl list-dependencies kubelet
```

**Kubernetes cluster not accessible:**
```bash
# Check if kubeconfig exists
ls -la ~/.kube/config

# Check cluster status
kubectl cluster-info dump

# Check node status
kubectl describe nodes
```

**Pods not starting:**
```bash
# Check pod events
kubectl get events --all-namespaces --sort-by='.lastTimestamp'

# Check specific pod logs
kubectl logs -n kube-system <pod-name>

# Restart failed pods
kubectl delete pods --all-namespaces --field-selector=status.phase=Failed
```

**MetalLB not working:**
```bash
# Check MetalLB pods
kubectl get pods -n metallb-system

# Check MetalLB configuration
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system

# Restart MetalLB
kubectl rollout restart daemonset/speaker -n metallb-system
kubectl rollout restart deployment/controller -n metallb-system
```

**ArgoCD not accessible:**
```bash
# Check ArgoCD pods
kubectl get pods -n argocd

# Check ArgoCD service
kubectl get svc -n argocd

# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### Best Practices for Autostart

**Regular verification:**
- Run autostart verification script monthly
- Test reboot scenarios in development environments
- Monitor service status with monitoring tools

**Backup configurations:**
- Backup `/etc/systemd/system/` directory
- Keep copies of Kubernetes manifests
- Document custom configurations

**Monitoring:**
- Set up alerts for service failures
- Monitor cluster health continuously
- Use tools like Prometheus and Grafana

### Recovery Procedures

**If autostart fails completely:**
```bash
# Manual recovery steps
sudo systemctl start containerd
sudo systemctl start kubelet

# Wait for cluster to be ready
kubectl wait --for=condition=Ready node --all --timeout=300s

# Check and restart failed pods
kubectl get pods --all-namespaces | grep -v Running
```

**Emergency cluster recovery:**
```bash
# Reset and reinitialize (DESTRUCTIVE - last resort)
sudo kubeadm reset
sudo systemctl restart containerd kubelet
# Re-run master installation script
```