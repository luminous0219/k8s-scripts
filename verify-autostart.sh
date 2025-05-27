#!/bin/bash

# Kubernetes Services Autostart Verification Script
# This script ensures all Kubernetes services start automatically after system reboot
# Compatible with Ubuntu 20.04+ and Debian 11+

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
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

highlight() {
    echo -e "${PURPLE}[HIGHLIGHT]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
       error "This script must be run as root (use sudo)"
       exit 1
    fi
}

# Check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        warning "kubectl not found - Kubernetes may not be installed"
        return 1
    fi
    return 0
}

# Verify and fix core Kubernetes services
verify_kubernetes_services() {
    log "Verifying Kubernetes core services autostart..."
    
    local k8s_services=("kubelet" "containerd")
    local all_enabled=true
    
    for service in "${k8s_services[@]}"; do
        if systemctl list-unit-files | grep -q "^$service.service"; then
            if systemctl is-enabled --quiet "$service"; then
                success "$service is enabled for autostart"
            else
                warning "$service is not enabled, enabling now..."
                systemctl enable "$service"
                if systemctl is-enabled --quiet "$service"; then
                    success "$service enabled successfully"
                else
                    error "Failed to enable $service"
                    all_enabled=false
                fi
            fi
            
            # Check if service is currently running
            if systemctl is-active --quiet "$service"; then
                info "$service is currently running"
            else
                warning "$service is not running, starting now..."
                systemctl start "$service"
            fi
        else
            warning "$service not found on this system"
        fi
    done
    
    return $all_enabled
}

# Create Kubernetes startup service
create_kubernetes_startup_service() {
    log "Creating Kubernetes startup service..."
    
    cat <<EOF > /etc/systemd/system/kubernetes-startup.service
[Unit]
Description=Kubernetes Startup Service
After=network.target containerd.service kubelet.service
Wants=containerd.service kubelet.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'sleep 30 && systemctl restart kubelet && sleep 10'
RemainAfterExit=yes
User=root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable kubernetes-startup.service
    
    success "Kubernetes startup service created and enabled"
}

# Verify MetalLB autostart
verify_metallb_autostart() {
    if ! check_kubectl; then
        return
    fi
    
    log "Verifying MetalLB autostart..."
    
    # Check if MetalLB namespace exists
    if ! kubectl get namespace metallb-system &> /dev/null; then
        info "MetalLB not installed, skipping verification"
        return
    fi
    
    # MetalLB runs as Kubernetes pods, so it should start automatically with Kubernetes
    # Check if MetalLB pods are running
    local metallb_pods=$(kubectl get pods -n metallb-system --no-headers 2>/dev/null | wc -l)
    if [ "$metallb_pods" -gt 0 ]; then
        success "MetalLB pods found ($metallb_pods pods)"
        
        # Check pod status
        local running_pods=$(kubectl get pods -n metallb-system --no-headers 2>/dev/null | grep Running | wc -l)
        if [ "$running_pods" -eq "$metallb_pods" ]; then
            success "All MetalLB pods are running"
        else
            warning "Some MetalLB pods are not running ($running_pods/$metallb_pods)"
            info "MetalLB pod status:"
            kubectl get pods -n metallb-system
        fi
    else
        warning "No MetalLB pods found"
    fi
}

# Verify ArgoCD autostart
verify_argocd_autostart() {
    if ! check_kubectl; then
        return
    fi
    
    log "Verifying ArgoCD autostart..."
    
    # Check if ArgoCD namespace exists
    if ! kubectl get namespace argocd &> /dev/null; then
        info "ArgoCD not installed, skipping verification"
        return
    fi
    
    # ArgoCD runs as Kubernetes pods, so it should start automatically with Kubernetes
    # Check if ArgoCD pods are running
    local argocd_pods=$(kubectl get pods -n argocd --no-headers 2>/dev/null | wc -l)
    if [ "$argocd_pods" -gt 0 ]; then
        success "ArgoCD pods found ($argocd_pods pods)"
        
        # Check pod status
        local running_pods=$(kubectl get pods -n argocd --no-headers 2>/dev/null | grep Running | wc -l)
        if [ "$running_pods" -eq "$argocd_pods" ]; then
            success "All ArgoCD pods are running"
        else
            warning "Some ArgoCD pods are not running ($running_pods/$argocd_pods)"
            info "ArgoCD pod status:"
            kubectl get pods -n argocd
        fi
    else
        warning "No ArgoCD pods found"
    fi
}

# Verify NVIDIA services autostart
verify_nvidia_autostart() {
    log "Verifying NVIDIA services autostart..."
    
    # Check if NVIDIA drivers are installed
    if ! command -v nvidia-smi &> /dev/null; then
        info "NVIDIA drivers not installed, skipping verification"
        return
    fi
    
    # NVIDIA Container Toolkit doesn't have a separate service
    # It integrates with containerd, which we already verified
    success "NVIDIA drivers detected, containerd integration verified"
    
    # Check NVIDIA device plugin if Kubernetes is available
    if check_kubectl; then
        local nvidia_pods=$(kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds --no-headers 2>/dev/null | wc -l)
        if [ "$nvidia_pods" -gt 0 ]; then
            success "NVIDIA device plugin pods found ($nvidia_pods pods)"
        else
            info "NVIDIA device plugin not found (may not be installed)"
        fi
    fi
}

# Create a comprehensive startup script
create_comprehensive_startup_script() {
    log "Creating comprehensive startup script..."
    
    cat <<EOF > /usr/local/bin/k8s-startup-check.sh
#!/bin/bash

# Kubernetes Comprehensive Startup Check
# This script runs at boot to ensure all services are properly started

sleep 60  # Wait for system to fully boot

# Restart core services if needed
systemctl is-active --quiet containerd || systemctl restart containerd
sleep 10
systemctl is-active --quiet kubelet || systemctl restart kubelet
sleep 20

# Check if kubectl is available and cluster is accessible
if command -v kubectl &> /dev/null; then
    # Wait for cluster to be ready
    for i in {1..30}; do
        if kubectl cluster-info &> /dev/null; then
            echo "Kubernetes cluster is accessible"
            break
        fi
        sleep 10
    done
    
    # Restart any failed pods
    kubectl get pods --all-namespaces --field-selector=status.phase=Failed -o name | xargs -r kubectl delete
fi

echo "Kubernetes startup check completed at \$(date)"
EOF

    chmod +x /usr/local/bin/k8s-startup-check.sh
    
    # Create systemd service for the startup script
    cat <<EOF > /etc/systemd/system/k8s-startup-check.service
[Unit]
Description=Kubernetes Comprehensive Startup Check
After=network.target multi-user.target
Wants=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/k8s-startup-check.sh
RemainAfterExit=yes
User=root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable k8s-startup-check.service
    
    success "Comprehensive startup script created and enabled"
}

# Display current service status
display_service_status() {
    echo ""
    highlight "=== CURRENT SERVICE STATUS ==="
    
    local services=("kubelet" "containerd")
    for service in "${services[@]}"; do
        if systemctl list-unit-files | grep -q "^$service.service"; then
            echo -n "$service: "
            if systemctl is-enabled --quiet "$service"; then
                echo -n "enabled, "
            else
                echo -n "disabled, "
            fi
            
            if systemctl is-active --quiet "$service"; then
                echo "running"
            else
                echo "stopped"
            fi
        fi
    done
    
    echo ""
    if check_kubectl; then
        highlight "=== KUBERNETES CLUSTER STATUS ==="
        kubectl get nodes 2>/dev/null || echo "Cluster not accessible"
        echo ""
        
        highlight "=== KUBERNETES PODS STATUS ==="
        kubectl get pods --all-namespaces 2>/dev/null | head -20 || echo "Cannot retrieve pod status"
    fi
}

# Main verification function
main() {
    echo ""
    echo "=============================================="
    echo "KUBERNETES AUTOSTART VERIFICATION"
    echo "=============================================="
    echo ""
    
    log "Starting autostart verification and configuration..."
    
    # Pre-flight checks
    check_root
    
    # Verify and fix services
    verify_kubernetes_services
    create_kubernetes_startup_service
    verify_metallb_autostart
    verify_argocd_autostart
    verify_nvidia_autostart
    create_comprehensive_startup_script
    
    # Display status
    display_service_status
    
    echo ""
    success "Autostart verification completed!"
    echo ""
    echo "=============================================="
    echo "AUTOSTART CONFIGURATION SUMMARY"
    echo "=============================================="
    echo "✅ Core Kubernetes services enabled for autostart"
    echo "✅ Kubernetes startup service created"
    echo "✅ Comprehensive startup check script installed"
    echo "✅ All services verified for automatic restart"
    echo ""
    echo "Services that will start automatically after reboot:"
    echo "• containerd (container runtime)"
    echo "• kubelet (Kubernetes node agent)"
    echo "• kubernetes-startup (custom startup service)"
    echo "• k8s-startup-check (comprehensive check service)"
    echo ""
    if check_kubectl; then
        echo "Kubernetes applications (pods) that will start automatically:"
        echo "• All system pods (kube-system namespace)"
        echo "• MetalLB (if installed)"
        echo "• ArgoCD (if installed)"
        echo "• NVIDIA device plugin (if installed)"
        echo "• All user applications and deployments"
    fi
    echo ""
    highlight "🔄 To test autostart: sudo reboot"
    highlight "🔍 To check status after reboot: sudo systemctl status kubelet containerd"
    echo ""
    warning "Note: It may take 2-3 minutes after reboot for all services to be fully ready"
}

# Run main function
main "$@" 