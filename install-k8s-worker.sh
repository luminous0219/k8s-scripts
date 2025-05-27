#!/bin/bash

# Kubernetes 1.33 Worker Node Installation Script
# This script installs and configures a Kubernetes worker node with the latest packages
# Compatible with Ubuntu 20.04+ and Debian 11+

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root (use sudo)"
   exit 1
fi

# Check OS compatibility
if ! grep -E "(Ubuntu|Debian)" /etc/os-release > /dev/null; then
    error "This script is designed for Ubuntu/Debian systems"
    exit 1
fi

log "Starting Kubernetes 1.33 Worker Node Installation..."

# Update system packages
log "Updating system packages..."
apt-get update -y
apt-get upgrade -y

# Install required packages
log "Installing required packages..."
apt-get install -y apt-transport-https ca-certificates curl gpg

# Disable swap
log "Disabling swap..."
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Load kernel modules
log "Loading required kernel modules..."
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# Set sysctl parameters
log "Configuring sysctl parameters..."
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

# Install containerd
log "Installing containerd..."
apt-get update -y
apt-get install -y containerd

# Configure containerd
log "Configuring containerd..."
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml

# Enable systemd cgroup driver
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Restart and enable containerd
systemctl restart containerd
systemctl enable containerd

# Add Kubernetes repository
log "Adding Kubernetes repository..."
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list

# Update package index
apt-get update -y

# Install Kubernetes components
log "Installing Kubernetes components (kubeadm, kubelet, kubectl)..."
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# Enable kubelet
systemctl enable kubelet

# Prompt for join command
echo ""
echo "=============================================="
echo "WORKER NODE JOIN PROCESS"
echo "=============================================="
echo ""
warning "You need the join command from your master node."
warning "This command was generated when you ran the master installation script."
warning "It should look like:"
echo "  kubeadm join <master-ip>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>"
echo ""

# Function to validate join command
validate_join_command() {
    local cmd="$1"
    if [[ $cmd =~ ^kubeadm\ join\ [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:6443\ --token\ [a-z0-9]+\.[a-z0-9]+\ --discovery-token-ca-cert-hash\ sha256:[a-f0-9]+$ ]]; then
        return 0
    else
        return 1
    fi
}

# Get join command from user
while true; do
    echo -n "Please enter the complete join command from your master node: "
    read -r JOIN_COMMAND
    
    if [ -z "$JOIN_COMMAND" ]; then
        error "Join command cannot be empty. Please try again."
        continue
    fi
    
    if validate_join_command "$JOIN_COMMAND"; then
        break
    else
        error "Invalid join command format. Please ensure you copied the complete command."
        echo "Expected format: kubeadm join <master-ip>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>"
        continue
    fi
done

# Execute join command
log "Joining the Kubernetes cluster..."
echo "Executing: $JOIN_COMMAND"

if eval "$JOIN_COMMAND"; then
    success "Successfully joined the Kubernetes cluster!"
else
    error "Failed to join the cluster. Please check:"
    error "1. Master node is accessible"
    error "2. Join command is correct and not expired"
    error "3. Network connectivity between nodes"
    error "4. Firewall settings allow required ports"
    exit 1
fi

# Verify node status
log "Verifying node status..."
sleep 10

# Check if kubelet is running
if systemctl is-active --quiet kubelet; then
    success "Kubelet service is running"
else
    warning "Kubelet service may not be running properly"
    systemctl status kubelet
fi

success "Kubernetes worker node installation completed successfully!"
echo ""
echo "=============================================="
echo "WORKER NODE SETUP COMPLETE"
echo "=============================================="
echo "1. Worker node has been configured and joined to the cluster"
echo "2. Kubelet service is running"
echo "3. Node should appear in 'kubectl get nodes' on the master"
echo ""
echo "To verify the node status from the master node, run:"
echo "  kubectl get nodes"
echo "  kubectl get pods -A"
echo ""
warning "Note: It may take a few minutes for the node to show as 'Ready'"
warning "Ensure all required ports are open in your firewall:"
warning "- 10250 (Kubelet API)"
warning "- 30000-32767 (NodePort Services)" 