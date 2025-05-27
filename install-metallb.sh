#!/bin/bash

# MetalLB v0.14.9 Installation Script for Kubernetes
# This script installs MetalLB load balancer with user-configurable IP ranges
# Compatible with Kubernetes clusters running on bare metal or VMs

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# MetalLB version
METALLB_VERSION="v0.14.9"

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

# Check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed or not in PATH"
        error "Please install kubectl first"
        exit 1
    fi
}

# Check if cluster is accessible
check_cluster() {
    if ! kubectl cluster-info &> /dev/null; then
        error "Cannot connect to Kubernetes cluster"
        error "Please ensure your cluster is running and kubectl is configured"
        exit 1
    fi
}

# Get current network information
get_network_info() {
    log "Detecting current network configuration..."
    
    # Get node IPs to help determine network range
    NODE_IPS=$(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "")
    
    if [ -n "$NODE_IPS" ]; then
        info "Detected node IPs: $NODE_IPS"
        
        # Try to determine network subnet from first node IP
        FIRST_IP=$(echo $NODE_IPS | awk '{print $1}')
        if [ -n "$FIRST_IP" ]; then
            # Extract network portion (assuming /24)
            NETWORK_BASE=$(echo $FIRST_IP | cut -d. -f1-3)
            info "Detected network base: ${NETWORK_BASE}.x"
        fi
    fi
    
    # Try to get local network info as fallback
    LOCAL_IP=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K\S+' || echo "")
    if [ -n "$LOCAL_IP" ]; then
        LOCAL_NETWORK_BASE=$(echo $LOCAL_IP | cut -d. -f1-3)
        info "Local network base: ${LOCAL_NETWORK_BASE}.x"
    fi
}

# Validate IP address format
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra ADDR <<< "$ip"
        for i in "${ADDR[@]}"; do
            if [[ $i -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# Validate IP range format
validate_ip_range() {
    local range=$1
    
    # Check if it's CIDR notation (e.g., 192.168.1.240/28)
    if [[ $range =~ ^([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})\/([0-9]{1,2})$ ]]; then
        local ip="${BASH_REMATCH[1]}"
        local cidr="${BASH_REMATCH[2]}"
        
        if validate_ip "$ip" && [[ $cidr -ge 1 && $cidr -le 32 ]]; then
            return 0
        fi
    fi
    
    # Check if it's range notation (e.g., 192.168.1.240-192.168.1.250)
    if [[ $range =~ ^([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})-([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})$ ]]; then
        local start_ip="${BASH_REMATCH[1]}"
        local end_ip="${BASH_REMATCH[2]}"
        
        if validate_ip "$start_ip" && validate_ip "$end_ip"; then
            return 0
        fi
    fi
    
    return 1
}

# Get IP range from user
get_ip_range() {
    echo ""
    echo "=============================================="
    echo "METALLB IP ADDRESS CONFIGURATION"
    echo "=============================================="
    echo ""
    
    info "MetalLB needs a range of IP addresses to assign to LoadBalancer services."
    info "These IPs must be:"
    info "  • Within your network's subnet"
    info "  • Not used by other devices (DHCP range, static IPs, etc.)"
    info "  • Routable from your network"
    echo ""
    
    info "You can specify the range in two formats:"
    echo ""
    
    info "1. CIDR notation examples:"
    info "   192.168.1.200/29    # Provides 8 IPs (.200-.207)"
    info "   192.168.1.240/28    # Provides 16 IPs (.240-.255)"
    info "   10.0.0.100/29       # Provides 8 IPs (.100-.107)"
    info "   172.16.1.50/29      # Provides 8 IPs (.50-.57)"
    echo ""
    
    info "2. Range notation examples:"
    info "   192.168.1.200-192.168.1.210    # Provides 11 IPs"
    info "   10.0.0.100-10.0.0.105          # Provides 6 IPs"
    info "   172.16.1.50-172.16.1.60        # Provides 11 IPs"
    echo ""
    
    if [ -n "$NETWORK_BASE" ]; then
        info "Your cluster network appears to be: ${NETWORK_BASE}.x"
        info "Choose a range within this subnet that's not used by:"
        info "  • DHCP server (often .100-.199 or .50-.150)"
        info "  • Static devices (routers, servers, printers)"
        info "  • Other infrastructure (Proxmox, ESXi, etc.)"
    fi
    
    echo ""
    warning "IMPORTANT: Verify your chosen range is available!"
    warning "Check your router/DHCP settings and ping test the IPs first."
    echo ""
    
    while true; do
        echo -n "Enter IP address range for MetalLB: "
        read -r IP_RANGE
        
        if [ -z "$IP_RANGE" ]; then
            error "IP range cannot be empty. Please try again."
            continue
        fi
        
        if validate_ip_range "$IP_RANGE"; then
            break
        else
            error "Invalid IP range format. Please use:"
            error "  • CIDR notation: 192.168.1.240/28"
            error "  • Range notation: 192.168.1.240-192.168.1.250"
            continue
        fi
    done
    
    success "IP range configured: $IP_RANGE"
}

# Install MetalLB
install_metallb() {
    log "Installing MetalLB $METALLB_VERSION..."
    
    # Apply MetalLB manifests
    kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/$METALLB_VERSION/config/manifests/metallb-native.yaml
    
    # Wait for MetalLB pods to be ready
    log "Waiting for MetalLB pods to be ready..."
    kubectl wait --namespace metallb-system \
        --for=condition=ready pod \
        --selector=app=metallb \
        --timeout=300s
    
    success "MetalLB installation completed"
}

# Configure MetalLB
configure_metallb() {
    log "Configuring MetalLB with IP range: $IP_RANGE"
    
    # Create MetalLB configuration
    cat <<EOF > /tmp/metallb-config.yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - $IP_RANGE
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
spec:
  ipAddressPools:
  - default-pool
EOF

    # Apply configuration
    kubectl apply -f /tmp/metallb-config.yaml
    
    # Clean up temp file
    rm -f /tmp/metallb-config.yaml
    
    success "MetalLB configuration applied"
}

# Create test service
create_test_service() {
    log "Creating test service to verify MetalLB functionality..."
    
    cat <<EOF > /tmp/metallb-test.yaml
apiVersion: v1
kind: Service
metadata:
  name: metallb-test-service
  namespace: default
spec:
  selector:
    app: metallb-test
  ports:
  - port: 80
    targetPort: 80
  type: LoadBalancer
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: metallb-test-deployment
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: metallb-test
  template:
    metadata:
      labels:
        app: metallb-test
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
EOF

    kubectl apply -f /tmp/metallb-test.yaml
    rm -f /tmp/metallb-test.yaml
    
    success "Test service created"
}

# Verify installation
verify_installation() {
    log "Verifying MetalLB installation..."
    
    # Check MetalLB pods
    echo ""
    info "MetalLB pods status:"
    kubectl get pods -n metallb-system
    
    # Check IP address pool
    echo ""
    info "IP Address Pool:"
    kubectl get ipaddresspool -n metallb-system
    
    # Check L2 advertisement
    echo ""
    info "L2 Advertisement:"
    kubectl get l2advertisement -n metallb-system
    
    # Check test service
    echo ""
    info "Test service status:"
    kubectl get svc metallb-test-service
    
    # Wait for external IP assignment
    log "Waiting for external IP assignment (this may take a few moments)..."
    
    for i in {1..30}; do
        EXTERNAL_IP=$(kubectl get svc metallb-test-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        if [ -n "$EXTERNAL_IP" ] && [ "$EXTERNAL_IP" != "null" ]; then
            success "External IP assigned: $EXTERNAL_IP"
            break
        fi
        echo -n "."
        sleep 2
    done
    
    if [ -z "$EXTERNAL_IP" ] || [ "$EXTERNAL_IP" = "null" ]; then
        warning "External IP not assigned yet. This might take a few more minutes."
        warning "Check with: kubectl get svc metallb-test-service"
    fi
}

# Cleanup test resources
cleanup_test() {
    echo ""
    echo -n "Do you want to remove the test service? (y/N): "
    read -r CLEANUP_CHOICE
    
    if [[ $CLEANUP_CHOICE =~ ^[Yy]$ ]]; then
        log "Cleaning up test resources..."
        kubectl delete deployment metallb-test-deployment --ignore-not-found=true
        kubectl delete service metallb-test-service --ignore-not-found=true
        success "Test resources cleaned up"
    else
        info "Test resources kept. You can access the test service at the assigned external IP."
        info "To clean up later, run:"
        info "  kubectl delete deployment metallb-test-deployment"
        info "  kubectl delete service metallb-test-service"
    fi
}

# Main installation function
main() {
    echo ""
    echo "=============================================="
    echo "METALLB $METALLB_VERSION INSTALLATION"
    echo "=============================================="
    echo ""
    
    log "Starting MetalLB installation..."
    
    # Pre-flight checks
    check_kubectl
    check_cluster
    get_network_info
    
    # Get user configuration
    get_ip_range
    
    # Install and configure MetalLB
    install_metallb
    configure_metallb
    create_test_service
    
    # Verify installation
    verify_installation
    
    # Cleanup option
    cleanup_test
    
    echo ""
    success "MetalLB installation completed successfully!"
    echo ""
    echo "=============================================="
    echo "METALLB INSTALLATION SUMMARY"
    echo "=============================================="
    echo "• MetalLB version: $METALLB_VERSION"
    echo "• IP address range: $IP_RANGE"
    echo "• Namespace: metallb-system"
    echo ""
    echo "Usage examples:"
    echo "• Create LoadBalancer service: kubectl expose deployment <name> --type=LoadBalancer --port=80"
    echo "• Check services: kubectl get svc"
    echo "• Check MetalLB status: kubectl get pods -n metallb-system"
    echo ""
    info "MetalLB will automatically assign external IPs from your configured range"
    info "to any service with type: LoadBalancer"
    echo ""
    warning "Remember to configure your firewall to allow traffic to the assigned IPs"
}

# Run main function
main "$@" 