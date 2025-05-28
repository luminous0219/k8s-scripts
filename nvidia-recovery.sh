#!/bin/bash

# NVIDIA Recovery Script for Kubernetes Worker Nodes
# This script helps recover from NVIDIA driver installation issues that prevent SSH/Kubernetes connectivity

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Logging functions
log() { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }
highlight() { echo -e "${PURPLE}[HIGHLIGHT]${NC} $1"; }

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
       error "This script must be run as root (use sudo)"
       exit 1
    fi
}

# Diagnose the current state
diagnose_system() {
    log "Diagnosing system state..."
    
    echo ""
    info "=== SYSTEM SERVICES STATUS ==="
    
    # Check containerd
    if systemctl is-active --quiet containerd; then
        success "containerd: RUNNING"
    else
        error "containerd: NOT RUNNING"
        CONTAINERD_FAILED=true
    fi
    
    # Check kubelet
    if systemctl is-active --quiet kubelet; then
        success "kubelet: RUNNING"
    else
        error "kubelet: NOT RUNNING"
        KUBELET_FAILED=true
    fi
    
    # Check NVIDIA driver
    if command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
        success "NVIDIA driver: WORKING"
        NVIDIA_WORKING=true
    else
        warning "NVIDIA driver: NOT WORKING"
        NVIDIA_WORKING=false
    fi
    
    # Check SSH
    if systemctl is-active --quiet ssh; then
        success "SSH: RUNNING"
    else
        error "SSH: NOT RUNNING"
        SSH_FAILED=true
    fi
    
    echo ""
    info "=== CONTAINERD CONFIGURATION ==="
    if [ -f /etc/containerd/config.toml ]; then
        info "Containerd config exists"
        if grep -q nvidia /etc/containerd/config.toml; then
            info "NVIDIA runtime configuration found in containerd"
        else
            warning "No NVIDIA runtime configuration in containerd"
        fi
    else
        error "Containerd config missing"
    fi
    
    echo ""
    info "=== NVIDIA MODULES ==="
    if lsmod | grep -q nvidia; then
        success "NVIDIA kernel modules loaded:"
        lsmod | grep nvidia
    else
        warning "NVIDIA kernel modules not loaded"
    fi
}

# Fix containerd issues
fix_containerd() {
    log "Fixing containerd issues..."
    
    # Stop containerd
    systemctl stop containerd || true
    
    # Backup current config
    if [ -f /etc/containerd/config.toml ]; then
        cp /etc/containerd/config.toml /etc/containerd/config.toml.backup.$(date +%s)
        info "Backed up containerd config"
    fi
    
    # Generate clean default config
    log "Generating clean containerd configuration..."
    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml
    
    # Enable systemd cgroup driver
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    
    # If NVIDIA is working, configure it properly
    if [ "$NVIDIA_WORKING" = true ]; then
        log "Configuring NVIDIA runtime for containerd..."
        if command -v nvidia-ctk &> /dev/null; then
            nvidia-ctk runtime configure --runtime=containerd --set-as-default
        else
            warning "nvidia-ctk not available, skipping NVIDIA runtime configuration"
        fi
    else
        info "NVIDIA not working, skipping NVIDIA runtime configuration"
    fi
    
    # Start containerd
    log "Starting containerd..."
    systemctl start containerd
    systemctl enable containerd
    
    # Wait for containerd to be ready
    sleep 10
    
    if systemctl is-active --quiet containerd; then
        success "containerd started successfully"
    else
        error "Failed to start containerd"
        systemctl status containerd --no-pager -l
        return 1
    fi
}

# Fix kubelet issues
fix_kubelet() {
    log "Fixing kubelet issues..."
    
    # Stop kubelet
    systemctl stop kubelet || true
    
    # Clean up kubelet state if corrupted
    if [ -d /var/lib/kubelet/pods ]; then
        log "Cleaning kubelet pod state..."
        rm -rf /var/lib/kubelet/pods/*
    fi
    
    # Remove corrupted kubelet config if exists
    if [ -f /var/lib/kubelet/config.yaml ]; then
        log "Backing up and removing kubelet config..."
        mv /var/lib/kubelet/config.yaml /var/lib/kubelet/config.yaml.backup.$(date +%s)
    fi
    
    # Ensure swap is disabled
    if swapon --show | grep -q "/"; then
        log "Disabling swap..."
        swapoff -a
    fi
    
    # Start kubelet
    log "Starting kubelet..."
    systemctl start kubelet
    systemctl enable kubelet
    
    # Wait for kubelet to start
    sleep 15
    
    if systemctl is-active --quiet kubelet; then
        success "kubelet started successfully"
    else
        warning "kubelet may still be starting up..."
        info "Kubelet status:"
        systemctl status kubelet --no-pager -l
    fi
}

# Fix SSH service
fix_ssh() {
    if [ "$SSH_FAILED" = true ]; then
        log "Fixing SSH service..."
        systemctl start ssh
        systemctl enable ssh
        
        if systemctl is-active --quiet ssh; then
            success "SSH service started"
        else
            error "Failed to start SSH service"
        fi
    fi
}

# Create recovery service for future issues
create_recovery_service() {
    log "Creating recovery service for future boot issues..."
    
    cat <<'EOF' > /etc/systemd/system/k8s-recovery.service
[Unit]
Description=Kubernetes Recovery Service
After=network.target containerd.service
Wants=containerd.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/k8s-recovery-check.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    cat <<'EOF' > /usr/local/bin/k8s-recovery-check.sh
#!/bin/bash

# Kubernetes Recovery Check Script
# Runs at boot to ensure services are working

exec > >(tee -a /var/log/k8s-recovery.log)
exec 2>&1

echo "=== K8s Recovery Check started at $(date) ==="

# Wait for system to stabilize
sleep 30

# Check and fix containerd
if ! systemctl is-active --quiet containerd; then
    echo "containerd not running, attempting to start..."
    systemctl start containerd
    sleep 10
fi

# Check and fix kubelet
if ! systemctl is-active --quiet kubelet; then
    echo "kubelet not running, attempting to start..."
    
    # Ensure containerd is ready
    if systemctl is-active --quiet containerd; then
        systemctl start kubelet
        sleep 15
    else
        echo "containerd not ready, cannot start kubelet"
    fi
fi

# Check SSH
if ! systemctl is-active --quiet ssh; then
    echo "SSH not running, starting..."
    systemctl start ssh
fi

echo "=== K8s Recovery Check completed at $(date) ==="
EOF

    chmod +x /usr/local/bin/k8s-recovery-check.sh
    systemctl enable k8s-recovery.service
    
    success "Recovery service created and enabled"
}

# Display recovery status
display_status() {
    echo ""
    success "Recovery process completed!"
    echo ""
    echo "=============================================="
    echo "RECOVERY STATUS"
    echo "=============================================="
    
    # Check services again
    if systemctl is-active --quiet containerd; then
        echo "✅ containerd: RUNNING"
    else
        echo "❌ containerd: NOT RUNNING"
    fi
    
    if systemctl is-active --quiet kubelet; then
        echo "✅ kubelet: RUNNING"
    else
        echo "⚠️  kubelet: NOT RUNNING (may still be starting)"
    fi
    
    if systemctl is-active --quiet ssh; then
        echo "✅ SSH: RUNNING"
    else
        echo "❌ SSH: NOT RUNNING"
    fi
    
    if [ "$NVIDIA_WORKING" = true ]; then
        echo "✅ NVIDIA: WORKING"
    else
        echo "⚠️  NVIDIA: NOT WORKING (may need reboot)"
    fi
    
    echo ""
    echo "Next steps:"
    echo "1. Wait 2-3 minutes for kubelet to fully start"
    echo "2. Check node status from master: kubectl get nodes"
    echo "3. If NVIDIA not working, run: nvidia-smi"
    echo "4. If still issues, check logs: journalctl -u kubelet -f"
    echo ""
    
    if [ "$NVIDIA_WORKING" = false ]; then
        warning "NVIDIA driver may need a reboot to work properly"
        warning "If the node is now accessible, you can reboot safely"
    fi
}

# Main recovery function
main() {
    echo ""
    echo "=============================================="
    echo "NVIDIA/KUBERNETES RECOVERY SCRIPT"
    echo "=============================================="
    echo ""
    
    log "Starting recovery process..."
    
    # Check if running as root
    check_root
    
    # Diagnose current state
    diagnose_system
    
    # Fix services in order
    if [ "$CONTAINERD_FAILED" = true ]; then
        fix_containerd
    fi
    
    if [ "$KUBELET_FAILED" = true ]; then
        fix_kubelet
    fi
    
    if [ "$SSH_FAILED" = true ]; then
        fix_ssh
    fi
    
    # Create recovery service
    create_recovery_service
    
    # Display final status
    display_status
}

# Run main function
main "$@" 