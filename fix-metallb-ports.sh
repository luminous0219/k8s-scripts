#!/bin/bash

# MetalLB Port Fix Script
# This script opens the required ports for MetalLB on all Kubernetes nodes
# Run this script on the master node after installing MetalLB

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
if [[ $EUID -eq 0 ]]; then
   error "This script should NOT be run as root. Run as regular user with sudo access."
   exit 1
fi

log "Starting MetalLB port configuration..."

# Function to open MetalLB ports
open_metallb_ports() {
    local node_ip=$1
    local node_name=$2
    
    log "Opening MetalLB ports on $node_name ($node_ip)..."
    
    if [ "$node_ip" = "localhost" ] || [ "$node_ip" = "$(hostname -I | awk '{print $1}')" ]; then
        # Local node (master)
        sudo ufw allow 7946/tcp comment "MetalLB memberlist TCP"
        sudo ufw allow 7946/udp comment "MetalLB memberlist UDP"
        success "Opened MetalLB ports on local node"
    else
        # Remote node (worker)
        if ssh -o ConnectTimeout=5 -o BatchMode=yes ml@$node_ip "exit" 2>/dev/null; then
            ssh ml@$node_ip "sudo ufw allow 7946/tcp comment 'MetalLB memberlist TCP' && sudo ufw allow 7946/udp comment 'MetalLB memberlist UDP'"
            success "Opened MetalLB ports on $node_name ($node_ip)"
        else
            error "Cannot connect to $node_name ($node_ip). Please run manually:"
            echo "  ssh ml@$node_ip"
            echo "  sudo ufw allow 7946/tcp"
            echo "  sudo ufw allow 7946/udp"
        fi
    fi
}

# Get node IPs from kubectl
log "Getting node information from Kubernetes cluster..."
if ! command -v kubectl &> /dev/null; then
    error "kubectl not found. Please ensure kubectl is installed and configured."
    exit 1
fi

# Check if we can access the cluster
if ! kubectl get nodes &> /dev/null; then
    error "Cannot access Kubernetes cluster. Please ensure kubectl is configured."
    exit 1
fi

# Get all node IPs
NODE_IPS=$(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')
NODE_NAMES=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')

# Convert to arrays
IFS=' ' read -ra IP_ARRAY <<< "$NODE_IPS"
IFS=' ' read -ra NAME_ARRAY <<< "$NODE_NAMES"

# Open ports on all nodes
for i in "${!IP_ARRAY[@]}"; do
    open_metallb_ports "${IP_ARRAY[$i]}" "${NAME_ARRAY[$i]}"
done

# Restart MetalLB speakers to refresh connections
log "Restarting MetalLB speaker pods to refresh connections..."
kubectl delete pods -n metallb-system -l component=speaker

# Wait for pods to restart
log "Waiting for MetalLB speakers to restart..."
kubectl wait --for=condition=Ready pod -l component=speaker -n metallb-system --timeout=60s

# Verify MetalLB status
log "Checking MetalLB status..."
kubectl get pods -n metallb-system

success "MetalLB port configuration completed successfully!"
echo ""
echo "=============================================="
echo "METALLB PORT CONFIGURATION COMPLETE"
echo "=============================================="
echo "Ports opened on all nodes:"
echo "- TCP 7946 (MetalLB memberlist)"
echo "- UDP 7946 (MetalLB memberlist)"
echo ""
echo "MetalLB speakers have been restarted and should now communicate properly."
echo ""
warning "If you still see connectivity issues, check your network firewall settings."
warning "Ensure ports 7946 TCP/UDP are open between all Kubernetes nodes." 