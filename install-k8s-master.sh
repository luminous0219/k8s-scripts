#!/bin/bash

# Kubernetes 1.33 Master Node Installation Script
# This script installs and configures a Kubernetes master node with the latest packages
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

log "Starting Kubernetes 1.33 Master Node Installation..."

# Update system packages
log "Updating system packages..."
apt-get update -y
apt-get upgrade -y

# Install required packages
log "Installing required packages..."
apt-get install -y apt-transport-https ca-certificates curl gpg

# Disable swap completely and permanently
disable_swap_completely() {
    log "Disabling swap completely and permanently..."
    
    # Turn off all swap immediately
    swapoff -a
    
    # Remove or comment out all swap entries in /etc/fstab
    sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
    sed -i '/swap/d' /etc/fstab 2>/dev/null || true
    
    # Remove any swap files
    if [ -f /swapfile ]; then
        log "Removing /swapfile..."
        rm -f /swapfile
    fi
    
    # Remove any other common swap files
    for swapfile in /swap.img /var/swap /swap; do
        if [ -f "$swapfile" ]; then
            log "Removing $swapfile..."
            rm -f "$swapfile"
        fi
    done
    
    # Disable swap in systemd
    systemctl mask swap.target
    
    # Create a systemd service to ensure swap stays disabled after reboot
    cat <<EOF > /etc/systemd/system/disable-swap.service
[Unit]
Description=Disable Swap
DefaultDependencies=false
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/sbin/swapoff -a
ExecStart=/bin/bash -c 'echo "Swap disabled for Kubernetes"'
RemainAfterExit=yes

[Install]
WantedBy=basic.target
EOF
    
    # Enable the disable-swap service
    systemctl daemon-reload
    systemctl enable disable-swap.service
    
    # Verify swap is disabled
    if [ "$(swapon --show | wc -l)" -eq 0 ]; then
        success "Swap has been completely disabled"
    else
        error "Swap is still active. Manual intervention may be required."
        swapon --show
    fi
    
    # Add vm.swappiness=0 to prevent any swap usage
    echo "vm.swappiness=0" >> /etc/sysctl.d/k8s.conf
    
    success "Swap has been permanently disabled and will remain disabled after reboot"
}

disable_swap_completely

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

# Initialize Kubernetes cluster
log "Initializing Kubernetes cluster..."
POD_CIDR="10.244.0.0/16"
kubeadm init --pod-network-cidr=$POD_CIDR --cri-socket=unix:///var/run/containerd/containerd.sock

# Set up kubectl for root user
log "Setting up kubectl for root user..."
mkdir -p /root/.kube
cp -i /etc/kubernetes/admin.conf /root/.kube/config
chown root:root /root/.kube/config

# Set up kubectl for regular user (if exists)
if [ -n "$SUDO_USER" ]; then
    log "Setting up kubectl for user: $SUDO_USER"
    USER_HOME=$(eval echo ~$SUDO_USER)
    mkdir -p $USER_HOME/.kube
    cp -i /etc/kubernetes/admin.conf $USER_HOME/.kube/config
    chown $SUDO_USER:$SUDO_USER $USER_HOME/.kube/config
fi

# Install Flannel CNI
log "Installing Flannel CNI..."
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Generate join command for worker nodes
log "Generating join command for worker nodes..."
JOIN_COMMAND=$(kubeadm token create --print-join-command)
echo "$JOIN_COMMAND" > /tmp/kubeadm-join-command.txt
chmod 644 /tmp/kubeadm-join-command.txt

# Wait for nodes to be ready
log "Waiting for master node to be ready..."
kubectl wait --for=condition=Ready node --all --timeout=300s

# Ensure all services are enabled for autostart
ensure_autostart_services() {
    log "Ensuring all services are enabled for autostart after reboot..."
    
    # Core Kubernetes services
    systemctl enable kubelet
    systemctl enable containerd
    
    # Verify services are enabled
    local services=("kubelet" "containerd")
    for service in "${services[@]}"; do
        if systemctl is-enabled --quiet "$service"; then
            success "$service is enabled for autostart"
        else
            warning "$service is not enabled, attempting to enable..."
            systemctl enable "$service"
        fi
    done
    
    # Create a systemd service to ensure Kubernetes starts properly after reboot
    cat <<EOF > /etc/systemd/system/kubernetes-startup.service
[Unit]
Description=Kubernetes Startup Service
After=network.target containerd.service kubelet.service
Wants=containerd.service kubelet.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'sleep 30 && systemctl restart kubelet'
RemainAfterExit=yes
User=root

[Install]
WantedBy=multi-user.target
EOF

    # Enable the startup service
    systemctl daemon-reload
    systemctl enable kubernetes-startup.service
    
    success "All services configured for autostart"
}

ensure_autostart_services

# Display cluster information
log "Displaying cluster information..."
kubectl get nodes
kubectl get pods -A

success "Kubernetes master node installation completed successfully!"
echo ""
echo "=============================================="
echo "IMPORTANT INFORMATION:"
echo "=============================================="
echo "1. Master node is ready and configured"
echo "2. Flannel CNI has been installed"
echo "3. Join command for worker nodes saved to: /tmp/kubeadm-join-command.txt"
echo ""
echo "To add worker nodes, run the following command on each worker:"
echo "=============================================="
cat /tmp/kubeadm-join-command.txt
echo "=============================================="
echo ""
echo "To manage the cluster, use kubectl commands:"
echo "  kubectl get nodes"
echo "  kubectl get pods -A"
echo "  kubectl cluster-info"
echo ""
warning "Remember to:"
warning "1. Copy the join command to your worker nodes"
warning "2. Ensure firewall allows required ports (6443, 2379-2380, 10250-10252)"
warning "3. Configure your network properly for pod communication" 