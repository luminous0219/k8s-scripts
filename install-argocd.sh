#!/bin/bash

# ArgoCD Installation Script for Kubernetes with MetalLB LoadBalancer
# This script installs ArgoCD and exposes it via MetalLB LoadBalancer with user-selectable IP
# Compatible with Kubernetes clusters running MetalLB

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# ArgoCD version (using stable)
ARGOCD_VERSION="stable"
ARGOCD_NAMESPACE="argocd"

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

highlight() {
    echo -e "${PURPLE}[HIGHLIGHT]${NC} $1"
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

# Check if MetalLB is installed
check_metallb() {
    log "Checking for MetalLB installation..."
    
    if ! kubectl get namespace metallb-system &> /dev/null; then
        error "MetalLB namespace not found"
        error "Please install MetalLB first using:"
        error "bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/luminous0219/k8s-scripts/main/install-metallb.sh)\""
        exit 1
    fi
    
    # Check if MetalLB pods are running
    METALLB_PODS=$(kubectl get pods -n metallb-system --no-headers 2>/dev/null | wc -l)
    if [ "$METALLB_PODS" -eq 0 ]; then
        error "No MetalLB pods found"
        error "Please ensure MetalLB is properly installed and running"
        exit 1
    fi
    
    success "MetalLB is installed and running"
}

# Get MetalLB IP pool information
get_metallb_info() {
    log "Getting MetalLB IP pool information..."
    
    # Get IP address pool
    IP_POOLS=$(kubectl get ipaddresspool -n metallb-system -o jsonpath='{.items[*].spec.addresses[*]}' 2>/dev/null || echo "")
    
    if [ -z "$IP_POOLS" ]; then
        error "No MetalLB IP address pools found"
        error "Please configure MetalLB with an IP address pool first"
        exit 1
    fi
    
    info "Available IP pools: $IP_POOLS"
    
    # Parse and display available ranges
    echo ""
    info "MetalLB IP address pools configured:"
    for pool in $IP_POOLS; do
        info "  • $pool"
    done
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

# Check if IP is in MetalLB range
check_ip_in_range() {
    local ip=$1
    local range=$2
    
    # Convert IP to integer for comparison
    ip_to_int() {
        local ip=$1
        local a b c d
        IFS='.' read -r a b c d <<< "$ip"
        echo $((a * 256**3 + b * 256**2 + c * 256 + d))
    }
    
    # Handle CIDR notation
    if [[ $range =~ ^([0-9.]+)/([0-9]+)$ ]]; then
        local network_ip="${BASH_REMATCH[1]}"
        local cidr="${BASH_REMATCH[2]}"
        
        local network_int=$(ip_to_int "$network_ip")
        local ip_int=$(ip_to_int "$ip")
        local mask=$((0xFFFFFFFF << (32 - cidr)))
        
        if [[ $((network_int & mask)) -eq $((ip_int & mask)) ]]; then
            return 0
        fi
    fi
    
    # Handle range notation
    if [[ $range =~ ^([0-9.]+)-([0-9.]+)$ ]]; then
        local start_ip="${BASH_REMATCH[1]}"
        local end_ip="${BASH_REMATCH[2]}"
        
        local start_int=$(ip_to_int "$start_ip")
        local end_int=$(ip_to_int "$end_ip")
        local ip_int=$(ip_to_int "$ip")
        
        if [[ $ip_int -ge $start_int && $ip_int -le $end_int ]]; then
            return 0
        fi
    fi
    
    return 1
}

# Get IP address from user
get_argocd_ip() {
    echo ""
    echo "=============================================="
    echo "ARGOCD LOADBALANCER IP CONFIGURATION"
    echo "=============================================="
    echo ""
    
    info "ArgoCD will be exposed via MetalLB LoadBalancer."
    info "You need to specify an IP address from your MetalLB pool."
    echo ""
    
    info "Available MetalLB IP pools:"
    for pool in $IP_POOLS; do
        info "  • $pool"
    done
    echo ""
    
    info "Examples of valid IPs (choose one that's not already in use):"
    for pool in $IP_POOLS; do
        if [[ $pool =~ ^([0-9.]+)/([0-9]+)$ ]]; then
            local base_ip="${BASH_REMATCH[1]}"
            local base=$(echo $base_ip | cut -d. -f1-3)
            local last=$(echo $base_ip | cut -d. -f4)
            info "  From $pool: ${base}.$((last+1)), ${base}.$((last+2)), ${base}.$((last+3))"
        elif [[ $pool =~ ^([0-9.]+)-([0-9.]+)$ ]]; then
            local start_ip="${BASH_REMATCH[1]}"
            local end_ip="${BASH_REMATCH[2]}"
            info "  From $pool: $start_ip, $(echo $start_ip | cut -d. -f1-3).$(($(echo $start_ip | cut -d. -f4) + 1))"
        fi
    done
    echo ""
    
    warning "IMPORTANT: Choose an IP that's not already assigned to other services!"
    warning "Check existing services: kubectl get svc --all-namespaces -o wide"
    echo ""
    
    while true; do
        echo -n "Enter IP address for ArgoCD LoadBalancer: "
        read -r ARGOCD_IP
        
        if [ -z "$ARGOCD_IP" ]; then
            error "IP address cannot be empty. Please try again."
            continue
        fi
        
        if ! validate_ip "$ARGOCD_IP"; then
            error "Invalid IP address format. Please enter a valid IP (e.g., 192.168.1.100)"
            continue
        fi
        
        # Check if IP is in any of the MetalLB ranges
        IP_IN_RANGE=false
        for pool in $IP_POOLS; do
            if check_ip_in_range "$ARGOCD_IP" "$pool"; then
                IP_IN_RANGE=true
                break
            fi
        done
        
        if [ "$IP_IN_RANGE" = false ]; then
            error "IP address $ARGOCD_IP is not in any MetalLB pool range"
            error "Please choose an IP from the available pools"
            continue
        fi
        
        # Check if IP is already in use
        EXISTING_IP=$(kubectl get svc --all-namespaces -o jsonpath='{range .items[*]}{.status.loadBalancer.ingress[0].ip}{"\n"}{end}' 2>/dev/null | grep "^$ARGOCD_IP$" || echo "")
        if [ -n "$EXISTING_IP" ]; then
            error "IP address $ARGOCD_IP is already in use by another service"
            error "Please choose a different IP address"
            continue
        fi
        
        break
    done
    
    success "ArgoCD IP configured: $ARGOCD_IP"
}

# Install ArgoCD
install_argocd() {
    log "Installing ArgoCD..."
    
    # Create namespace
    kubectl create namespace $ARGOCD_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    
    # Install ArgoCD
    kubectl apply -n $ARGOCD_NAMESPACE -f https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/install.yaml
    
    # Wait for ArgoCD pods to be ready
    log "Waiting for ArgoCD pods to be ready (this may take a few minutes)..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n $ARGOCD_NAMESPACE --timeout=300s
    
    success "ArgoCD installation completed"
}

# Configure ArgoCD LoadBalancer
configure_loadbalancer() {
    log "Configuring ArgoCD LoadBalancer with IP: $ARGOCD_IP"
    
    # Create LoadBalancer service with specific IP
    cat <<EOF > /tmp/argocd-loadbalancer.yaml
apiVersion: v1
kind: Service
metadata:
  name: argocd-server-loadbalancer
  namespace: $ARGOCD_NAMESPACE
  labels:
    app.kubernetes.io/component: server
    app.kubernetes.io/name: argocd-server
    app.kubernetes.io/part-of: argocd
spec:
  type: LoadBalancer
  loadBalancerIP: $ARGOCD_IP
  ports:
  - name: https
    port: 443
    protocol: TCP
    targetPort: 8080
  - name: grpc
    port: 80
    protocol: TCP
    targetPort: 8080
  selector:
    app.kubernetes.io/name: argocd-server
EOF

    kubectl apply -f /tmp/argocd-loadbalancer.yaml
    rm -f /tmp/argocd-loadbalancer.yaml
    
    success "ArgoCD LoadBalancer service created"
}

# Get ArgoCD admin password
get_admin_password() {
    log "Retrieving ArgoCD admin password..."
    
    # Wait for the secret to be created
    for i in {1..30}; do
        if kubectl get secret argocd-initial-admin-secret -n $ARGOCD_NAMESPACE &> /dev/null; then
            break
        fi
        echo -n "."
        sleep 2
    done
    
    ADMIN_PASSWORD=$(kubectl -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    
    if [ -z "$ADMIN_PASSWORD" ]; then
        warning "Could not retrieve admin password automatically"
        warning "You can get it later with:"
        warning "kubectl -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
    else
        success "Admin password retrieved"
    fi
}

# Create sample application
create_sample_app() {
    echo ""
    echo -n "Do you want to create a sample guestbook application? (y/N): "
    read -r CREATE_SAMPLE
    
    if [[ $CREATE_SAMPLE =~ ^[Yy]$ ]]; then
        log "Creating sample guestbook application..."
        
        cat <<EOF > /tmp/guestbook-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  namespace: $ARGOCD_NAMESPACE
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps.git
    targetRevision: HEAD
    path: guestbook
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: false
      selfHeal: false
    syncOptions:
    - CreateNamespace=true
EOF

        kubectl apply -f /tmp/guestbook-app.yaml
        rm -f /tmp/guestbook-app.yaml
        
        success "Sample guestbook application created"
        info "You can sync it from the ArgoCD UI"
    fi
}

# Verify installation
verify_installation() {
    log "Verifying ArgoCD installation..."
    
    # Check ArgoCD pods
    echo ""
    info "ArgoCD pods status:"
    kubectl get pods -n $ARGOCD_NAMESPACE
    
    # Check LoadBalancer service
    echo ""
    info "ArgoCD LoadBalancer service:"
    kubectl get svc argocd-server-loadbalancer -n $ARGOCD_NAMESPACE
    
    # Wait for LoadBalancer IP assignment
    log "Waiting for LoadBalancer IP assignment..."
    
    for i in {1..30}; do
        ASSIGNED_IP=$(kubectl get svc argocd-server-loadbalancer -n $ARGOCD_NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        if [ -n "$ASSIGNED_IP" ] && [ "$ASSIGNED_IP" != "null" ]; then
            success "LoadBalancer IP assigned: $ASSIGNED_IP"
            break
        fi
        echo -n "."
        sleep 2
    done
    
    if [ -z "$ASSIGNED_IP" ] || [ "$ASSIGNED_IP" = "null" ]; then
        warning "LoadBalancer IP not assigned yet. This might take a few more minutes."
        warning "Check with: kubectl get svc argocd-server-loadbalancer -n $ARGOCD_NAMESPACE"
    fi
}

# Display access information
display_access_info() {
    echo ""
    success "ArgoCD installation completed successfully!"
    echo ""
    echo "=============================================="
    echo "ARGOCD ACCESS INFORMATION"
    echo "=============================================="
    echo ""
    highlight "ArgoCD UI Access:"
    highlight "  URL: https://$ARGOCD_IP"
    highlight "  Username: admin"
    if [ -n "$ADMIN_PASSWORD" ]; then
        highlight "  Password: $ADMIN_PASSWORD"
    else
        highlight "  Password: Run the command below to get it"
        echo "    kubectl -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
    fi
    echo ""
    
    info "Alternative access methods:"
    info "  • HTTP: http://$ARGOCD_IP:80 (redirects to HTTPS)"
    info "  • gRPC: $ARGOCD_IP:80 (for ArgoCD CLI)"
    echo ""
    
    warning "IMPORTANT NOTES:"
    warning "• ArgoCD uses a self-signed certificate - your browser will show a security warning"
    warning "• Click 'Advanced' and 'Proceed to $ARGOCD_IP' to continue"
    warning "• For production use, configure a proper TLS certificate"
    echo ""
    
    info "Useful commands:"
    info "• Check ArgoCD status: kubectl get pods -n $ARGOCD_NAMESPACE"
    info "• Get admin password: kubectl -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
    info "• View services: kubectl get svc -n $ARGOCD_NAMESPACE"
    info "• View applications: kubectl get applications -n $ARGOCD_NAMESPACE"
    echo ""
    
    if [[ $CREATE_SAMPLE =~ ^[Yy]$ ]]; then
        info "Sample guestbook application created!"
        info "• Login to ArgoCD UI and sync the 'guestbook' application"
        info "• After syncing, access guestbook at: kubectl port-forward svc/guestbook-ui 8081:80"
    fi
    echo ""
    
    highlight "Next steps:"
    highlight "1. Open https://$ARGOCD_IP in your browser"
    highlight "2. Login with admin/$ADMIN_PASSWORD"
    highlight "3. Explore the ArgoCD UI and manage your applications"
    highlight "4. Create your own applications pointing to your Git repositories"
}

# Main installation function
main() {
    echo ""
    echo "=============================================="
    echo "ARGOCD INSTALLATION WITH METALLB"
    echo "=============================================="
    echo ""
    
    log "Starting ArgoCD installation..."
    
    # Pre-flight checks
    check_kubectl
    check_cluster
    check_metallb
    get_metallb_info
    
    # Get user configuration
    get_argocd_ip
    
    # Install and configure ArgoCD
    install_argocd
    configure_loadbalancer
    get_admin_password
    create_sample_app
    
    # Verify installation
    verify_installation
    
    # Display access information
    display_access_info
}

# Run main function
main "$@" 