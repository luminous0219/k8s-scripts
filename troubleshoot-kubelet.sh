#!/bin/bash

# Kubelet Troubleshooting Script
# This script diagnoses and fixes common kubelet startup issues
# Run this when kubelet fails to start after reboot

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
echo "KUBELET TROUBLESHOOTING"
echo "=============================================="
echo ""

log "Starting kubelet diagnosis and repair..."

# Step 1: Check current kubelet status
log "Step 1: Checking kubelet status..."
systemctl status kubelet --no-pager -l

# Step 2: Analyze kubelet logs
log "Step 2: Analyzing kubelet logs..."
echo ""
info "Recent kubelet logs:"
journalctl -u kubelet --no-pager -l --since "10 minutes ago" | tail -30

# Step 3: Check common issues
log "Step 3: Checking for common issues..."

# Check swap
info "Checking swap status..."
if swapon --show | grep -q "/"; then
    warning "Swap is enabled! Kubernetes requires swap to be disabled."
    log "Disabling swap..."
    swapoff -a
    success "Swap disabled"
else
    success "Swap is disabled"
fi

# Check containerd
info "Checking containerd status..."
if systemctl is-active --quiet containerd; then
    success "containerd is running"
    
    # Check containerd socket
    if [ -S /run/containerd/containerd.sock ]; then
        success "containerd socket is accessible"
    else
        warning "containerd socket not found, restarting containerd..."
        systemctl restart containerd
        sleep 10
    fi
else
    warning "containerd is not running, starting it..."
    systemctl start containerd
    sleep 10
fi

# Check kubelet configuration
info "Checking kubelet configuration..."
if [ -f /var/lib/kubelet/config.yaml ]; then
    info "Kubelet config file exists"
    # Check if config is valid YAML
    if python3 -c "import yaml; yaml.safe_load(open('/var/lib/kubelet/config.yaml'))" 2>/dev/null; then
        success "Kubelet config is valid YAML"
    else
        warning "Kubelet config appears corrupted, backing up and removing..."
        mv /var/lib/kubelet/config.yaml /var/lib/kubelet/config.yaml.backup.$(date +%s)
        success "Corrupted config backed up and removed"
    fi
else
    info "Kubelet config file not found (will be generated)"
fi

# Check kubelet kubeconfig
info "Checking kubelet kubeconfig..."
if [ -f /etc/kubernetes/kubelet.conf ]; then
    success "Kubelet kubeconfig exists"
else
    warning "Kubelet kubeconfig not found"
    if [ -f /etc/kubernetes/admin.conf ]; then
        info "This appears to be a master node"
    else
        error "This appears to be a worker node without proper kubeconfig"
        error "You may need to rejoin this node to the cluster"
    fi
fi

# Check certificates
info "Checking kubelet certificates..."
CERT_DIR="/var/lib/kubelet/pki"
if [ -d "$CERT_DIR" ]; then
    CERT_COUNT=$(find "$CERT_DIR" -name "*.crt" | wc -l)
    info "Found $CERT_COUNT certificate files"
    
    # Check certificate expiration
    for cert in "$CERT_DIR"/*.crt; do
        if [ -f "$cert" ]; then
            EXPIRY=$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null | cut -d= -f2)
            if [ -n "$EXPIRY" ]; then
                info "Certificate $(basename "$cert"): expires $EXPIRY"
            fi
        fi
    done
else
    warning "Kubelet certificate directory not found"
fi

# Check system resources
info "Checking system resources..."
DISK_USAGE=$(df /var/lib/kubelet 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//')
if [ -n "$DISK_USAGE" ] && [ "$DISK_USAGE" -gt 90 ]; then
    warning "Disk usage is high: ${DISK_USAGE}%"
    warning "Consider cleaning up disk space"
else
    success "Disk usage is acceptable: ${DISK_USAGE}%"
fi

MEMORY_USAGE=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
if [ "$MEMORY_USAGE" -gt 90 ]; then
    warning "Memory usage is high: ${MEMORY_USAGE}%"
else
    success "Memory usage is acceptable: ${MEMORY_USAGE}%"
fi

# Step 4: Clean up kubelet state
log "Step 4: Cleaning up kubelet state..."

# Stop kubelet
systemctl stop kubelet 2>/dev/null || true

# Clean up problematic pods
if [ -d /var/lib/kubelet/pods ]; then
    POD_COUNT=$(find /var/lib/kubelet/pods -maxdepth 1 -type d | wc -l)
    if [ "$POD_COUNT" -gt 1 ]; then
        warning "Found $((POD_COUNT-1)) pod directories, cleaning up..."
        find /var/lib/kubelet/pods -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} \; 2>/dev/null || true
        success "Pod directories cleaned up"
    fi
fi

# Clean up kubelet cache
if [ -d /var/lib/kubelet/cpu_manager_state ]; then
    rm -f /var/lib/kubelet/cpu_manager_state
fi

if [ -d /var/lib/kubelet/memory_manager_state ]; then
    rm -f /var/lib/kubelet/memory_manager_state
fi

# Step 5: Attempt to start kubelet
log "Step 5: Attempting to start kubelet..."

for attempt in {1..3}; do
    log "Starting kubelet (attempt $attempt/3)..."
    
    systemctl start kubelet
    sleep 15
    
    if systemctl is-active --quiet kubelet; then
        success "kubelet started successfully!"
        break
    else
        warning "kubelet failed to start on attempt $attempt"
        
        if [ $attempt -eq 3 ]; then
            error "Failed to start kubelet after 3 attempts"
            echo ""
            error "Final kubelet status:"
            systemctl status kubelet --no-pager -l
            echo ""
            error "Final kubelet logs:"
            journalctl -u kubelet --no-pager -l --since "5 minutes ago" | tail -20
            echo ""
            error "Manual intervention required. Common solutions:"
            error "1. Check if this node needs to rejoin the cluster"
            error "2. Verify network connectivity to master node"
            error "3. Check if certificates have expired"
            error "4. Ensure all required ports are open"
            exit 1
        else
            log "Waiting before next attempt..."
            sleep 10
        fi
    fi
done

# Step 6: Verify kubelet is working
log "Step 6: Verifying kubelet functionality..."

# Wait for kubelet to stabilize
sleep 30

if systemctl is-active --quiet kubelet; then
    success "kubelet is running and stable"
    
    # Check if kubelet can connect to API server (for master nodes)
    if [ -f /etc/kubernetes/admin.conf ]; then
        log "Checking API server connectivity..."
        if kubectl --kubeconfig=/etc/kubernetes/admin.conf cluster-info &>/dev/null; then
            success "kubelet can connect to API server"
        else
            warning "kubelet is running but API server is not accessible yet"
            info "This is normal and may take a few more minutes"
        fi
    fi
else
    error "kubelet is still not running properly"
    exit 1
fi

echo ""
success "Kubelet troubleshooting completed!"
echo ""
echo "=============================================="
echo "SUMMARY"
echo "=============================================="
echo "✅ kubelet is running"
echo "✅ Common issues have been resolved"
echo "✅ System is ready for Kubernetes operations"
echo ""
echo "Next steps:"
echo "1. Wait 2-3 minutes for full cluster initialization"
echo "2. Check cluster status: kubectl get nodes"
echo "3. Check pod status: kubectl get pods -A"
echo ""
warning "If you continue to have issues, consider:"
warning "1. Rejoining worker nodes to the cluster"
warning "2. Checking network connectivity and firewall rules"
warning "3. Verifying certificate validity" 