#!/bin/bash

# Kubernetes Startup Fix Script
# This script fixes Kubernetes startup issues after reboot
# Run this when kubectl commands fail with connection refused errors

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root (use sudo)"
   exit 1
fi

echo ""
echo "=============================================="
echo "KUBERNETES STARTUP FIX"
echo "=============================================="
echo ""

log "Diagnosing and fixing Kubernetes startup issues..."

# Step 1: Check and restart core services
log "Step 1: Checking core services..."

info "Checking containerd status..."
if systemctl is-active --quiet containerd; then
    success "containerd is running"
else
    warning "containerd is not running, starting it..."
    systemctl start containerd
    sleep 10
    if systemctl is-active --quiet containerd; then
        success "containerd started successfully"
    else
        error "Failed to start containerd"
        systemctl status containerd
        exit 1
    fi
fi

info "Checking kubelet status..."
if systemctl is-active --quiet kubelet; then
    success "kubelet is running"
else
    warning "kubelet is not running, starting it..."
    systemctl start kubelet
    sleep 15
    if systemctl is-active --quiet kubelet; then
        success "kubelet started successfully"
    else
        error "Failed to start kubelet"
        systemctl status kubelet
        exit 1
    fi
fi

# Step 2: Check if this is a master node
log "Step 2: Checking node type..."

if [ -f /etc/kubernetes/admin.conf ]; then
    info "Master node detected"
    KUBECONFIG_FILE="/etc/kubernetes/admin.conf"
    IS_MASTER=true
else
    info "Worker node detected"
    IS_MASTER=false
fi

# Step 3: For master nodes, check control plane
if [ "$IS_MASTER" = true ]; then
    log "Step 3: Checking control plane components..."
    
    # Check static pod manifests
    info "Checking static pod manifests..."
    if [ -d /etc/kubernetes/manifests ]; then
        MANIFEST_COUNT=$(ls -1 /etc/kubernetes/manifests/*.yaml 2>/dev/null | wc -l)
        info "Found $MANIFEST_COUNT static pod manifests"
        ls -la /etc/kubernetes/manifests/
    else
        error "Static pod manifests directory not found!"
        exit 1
    fi
    
    # Restart kubelet to ensure it picks up static pods
    log "Restarting kubelet to ensure static pods are loaded..."
    systemctl restart kubelet
    sleep 30
    
    # Wait for API server to be accessible
    log "Waiting for API server to become accessible..."
    for i in {1..30}; do
        if kubectl --kubeconfig="$KUBECONFIG_FILE" cluster-info &> /dev/null; then
            success "API server is accessible!"
            break
        else
            echo -n "."
            sleep 10
        fi
        
        if [ $i -eq 30 ]; then
            echo ""
            error "API server is still not accessible after 5 minutes"
            
            # Show diagnostic information
            warning "Diagnostic information:"
            echo "Kubelet status:"
            systemctl status kubelet --no-pager -l
            echo ""
            echo "Kubelet logs (last 20 lines):"
            journalctl -u kubelet --no-pager -l --since "10 minutes ago" | tail -20
            echo ""
            echo "Container runtime status:"
            systemctl status containerd --no-pager -l
            
            exit 1
        fi
    done
    
    # Check control plane pods
    log "Checking control plane pods..."
    kubectl --kubeconfig="$KUBECONFIG_FILE" get pods -n kube-system | grep -E "(kube-apiserver|kube-controller-manager|kube-scheduler|etcd)"
    
    # Wait for nodes to be ready
    log "Waiting for nodes to be ready..."
    kubectl --kubeconfig="$KUBECONFIG_FILE" wait --for=condition=Ready node --all --timeout=300s
    
    # Clean up any failed pods
    log "Cleaning up failed pods..."
    FAILED_PODS=$(kubectl --kubeconfig="$KUBECONFIG_FILE" get pods --all-namespaces --field-selector=status.phase=Failed -o name 2>/dev/null || echo "")
    if [ -n "$FAILED_PODS" ]; then
        echo "$FAILED_PODS" | xargs kubectl --kubeconfig="$KUBECONFIG_FILE" delete
        success "Cleaned up failed pods"
    else
        info "No failed pods found"
    fi
fi

# Step 4: Final verification
log "Step 4: Final verification..."

if [ "$IS_MASTER" = true ]; then
    info "Cluster status:"
    kubectl --kubeconfig="$KUBECONFIG_FILE" cluster-info
    echo ""
    
    info "Node status:"
    kubectl --kubeconfig="$KUBECONFIG_FILE" get nodes
    echo ""
    
    info "System pods status:"
    kubectl --kubeconfig="$KUBECONFIG_FILE" get pods -n kube-system
    echo ""
    
    # Set up kubectl for current user if not root
    if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
        USER_HOME=$(eval echo ~$SUDO_USER)
        if [ -f "$USER_HOME/.kube/config" ]; then
            info "kubectl is already configured for user $SUDO_USER"
        else
            log "Setting up kubectl for user $SUDO_USER..."
            mkdir -p "$USER_HOME/.kube"
            cp -i /etc/kubernetes/admin.conf "$USER_HOME/.kube/config"
            chown $SUDO_USER:$SUDO_USER "$USER_HOME/.kube/config"
            success "kubectl configured for user $SUDO_USER"
        fi
    fi
fi

echo ""
success "Kubernetes startup fix completed!"
echo ""
echo "=============================================="
echo "SUMMARY"
echo "=============================================="
echo "✅ Core services (containerd, kubelet) are running"
if [ "$IS_MASTER" = true ]; then
    echo "✅ Control plane is accessible"
    echo "✅ Nodes are ready"
    echo "✅ System pods are running"
fi
echo ""
echo "You can now use kubectl commands:"
echo "  kubectl get nodes"
echo "  kubectl get pods -A"
echo "  kubectl cluster-info"
echo ""
warning "If you continue to have issues after reboot, run:"
warning "sudo bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/luminous0219/k8s-scripts/main/verify-autostart.sh)\"" 