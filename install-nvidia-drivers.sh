#!/bin/bash

# NVIDIA GPU Drivers Installation Script for Kubernetes Worker Nodes
# This script installs NVIDIA drivers, container toolkit, and Kubernetes device plugin
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

# NVIDIA versions
NVIDIA_DRIVER_VERSION="550"  # Latest stable branch
NVIDIA_DEVICE_PLUGIN_VERSION="v0.16.2"

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

# Check OS compatibility
check_os() {
    if ! grep -E "(Ubuntu|Debian)" /etc/os-release > /dev/null; then
        error "This script is designed for Ubuntu/Debian systems"
        exit 1
    fi
    
    # Get OS version for compatibility checks
    OS_VERSION=$(grep VERSION_ID /etc/os-release | cut -d'"' -f2)
    OS_NAME=$(grep '^ID=' /etc/os-release | cut -d'=' -f2)
    
    info "Detected OS: $OS_NAME $OS_VERSION"
}

# Check for NVIDIA GPUs
detect_nvidia_gpu() {
    log "Detecting NVIDIA GPUs..."
    
    if ! command -v lspci &> /dev/null; then
        log "Installing pciutils for GPU detection..."
        apt-get update -y
        apt-get install -y pciutils
    fi
    
    GPU_COUNT=$(lspci | grep -i nvidia | grep -i vga | wc -l)
    GPU_INFO=$(lspci | grep -i nvidia | grep -i vga || echo "")
    
    if [ "$GPU_COUNT" -eq 0 ]; then
        error "No NVIDIA GPUs detected on this system"
        error "This script is intended for systems with NVIDIA GPUs"
        echo ""
        info "Available GPUs:"
        lspci | grep -i vga || echo "No VGA devices found"
        exit 1
    fi
    
    success "Found $GPU_COUNT NVIDIA GPU(s):"
    echo "$GPU_INFO" | while read -r line; do
        info "  • $line"
    done
}

# Check if Kubernetes is installed
check_kubernetes() {
    log "Checking Kubernetes installation..."
    
    if ! command -v kubectl &> /dev/null; then
        warning "kubectl not found - this script is designed for Kubernetes worker nodes"
        warning "Continuing with driver installation only..."
        K8S_AVAILABLE=false
        return
    fi
    
    if ! systemctl is-active --quiet kubelet; then
        warning "kubelet service is not running"
        warning "Continuing with driver installation only..."
        K8S_AVAILABLE=false
        return
    fi
    
    # Test kubectl connectivity to the cluster
    log "Testing kubectl connectivity to Kubernetes cluster..."
    if ! kubectl cluster-info &> /dev/null; then
        warning "kubectl cannot connect to Kubernetes cluster"
        warning "This is normal for worker nodes that don't have direct API access"
        warning "Device plugin installation will be skipped"
        K8S_AVAILABLE=false
        return
    fi
    
    # Additional check: try to list nodes
    if ! kubectl get nodes &> /dev/null; then
        warning "kubectl cannot list nodes - insufficient permissions or connectivity issues"
        warning "Device plugin installation will be skipped"
        K8S_AVAILABLE=false
        return
    fi
    
    success "Kubernetes detected and kubectl connectivity verified"
    K8S_AVAILABLE=true
}

# Remove existing NVIDIA installations
cleanup_existing() {
    log "Cleaning up existing NVIDIA installations..."
    
    # Remove existing NVIDIA packages
    apt-get remove --purge -y nvidia-* libnvidia-* || true
    apt-get autoremove -y || true
    
    # Remove existing drivers
    if command -v nvidia-uninstall &> /dev/null; then
        nvidia-uninstall --silent || true
    fi
    
    success "Cleanup completed"
}

# Install prerequisites
install_prerequisites() {
    log "Installing prerequisites..."
    
    # Update package index
    apt-get update -y
    
    # Install required packages
    apt-get install -y \
        build-essential \
        dkms \
        linux-headers-$(uname -r) \
        pkg-config \
        libglvnd-dev \
        curl \
        gnupg \
        ca-certificates \
        software-properties-common
    
    success "Prerequisites installed"
}

# Install NVIDIA drivers
install_nvidia_drivers() {
    log "Installing NVIDIA drivers (version $NVIDIA_DRIVER_VERSION)..."
    
    # Add NVIDIA PPA for latest drivers
    add-apt-repository ppa:graphics-drivers/ppa -y
    apt-get update -y
    
    # Install NVIDIA driver
    apt-get install -y nvidia-driver-$NVIDIA_DRIVER_VERSION
    
    # Install additional NVIDIA packages
    apt-get install -y \
        nvidia-settings \
        nvidia-prime
    
    success "NVIDIA drivers installed"
}

# Install NVIDIA Container Toolkit
install_container_toolkit() {
    log "Installing NVIDIA Container Toolkit..."
    
    # Add NVIDIA Container Toolkit repository
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    
    apt-get update -y
    
    # Show available versions for debugging
    info "Available NVIDIA Container Toolkit versions:"
    apt-cache policy nvidia-container-toolkit | grep -A 5 "Version table" || true
    
    # Install NVIDIA Container Toolkit (latest available version)
    log "Installing NVIDIA Container Toolkit (latest version)..."
    if ! apt-get install -y nvidia-container-toolkit; then
        warning "Failed to install nvidia-container-toolkit, trying to fix dependencies..."
        
        # Show dependency information
        info "Checking package dependencies:"
        apt-cache depends nvidia-container-toolkit || true
        
        # Try to fix broken dependencies
        apt-get install -f -y
        
        # Try again
        if ! apt-get install -y nvidia-container-toolkit; then
            error "Failed to install NVIDIA Container Toolkit"
            error "Please check the package dependencies manually:"
            error "apt-cache policy nvidia-container-toolkit"
            error "apt-cache policy nvidia-container-toolkit-base"
            exit 1
        fi
    fi
    
    success "NVIDIA Container Toolkit installed"
}

# Configure containerd for NVIDIA
configure_containerd() {
    log "Configuring containerd for NVIDIA support..."
    
    # Backup current containerd config
    if [ -f /etc/containerd/config.toml ]; then
        cp /etc/containerd/config.toml /etc/containerd/config.toml.backup.$(date +%s)
        info "Backed up existing containerd config"
    fi
    
    # Generate default containerd config if it doesn't exist
    if [ ! -f /etc/containerd/config.toml ]; then
        mkdir -p /etc/containerd
        containerd config default > /etc/containerd/config.toml
    fi
    
    # Ensure systemd cgroup driver is enabled (required for Kubernetes)
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    
    # Test containerd config before adding NVIDIA runtime
    log "Testing containerd configuration..."
    if ! containerd --config /etc/containerd/config.toml config dump > /dev/null; then
        error "Containerd configuration is invalid, regenerating..."
        containerd config default > /etc/containerd/config.toml
        sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    fi
    
    # Restart containerd with basic config first
    log "Restarting containerd with basic configuration..."
    systemctl restart containerd
    sleep 10
    
    # Verify containerd is working before adding NVIDIA runtime
    if ! systemctl is-active --quiet containerd; then
        error "Failed to start containerd with basic configuration"
        exit 1
    fi
    
    success "Containerd is running with basic configuration"
    
    # Now configure NVIDIA runtime
    log "Adding NVIDIA runtime configuration..."
    if nvidia-ctk runtime configure --runtime=containerd; then
        success "NVIDIA runtime configuration added"
        
        # Test the new configuration
        log "Testing NVIDIA runtime configuration..."
        if containerd --config /etc/containerd/config.toml config dump > /dev/null; then
            success "NVIDIA runtime configuration is valid"
            
            # Restart containerd with NVIDIA configuration
            log "Restarting containerd with NVIDIA configuration..."
            systemctl restart containerd
            sleep 15
            
            # Verify containerd is still working
            if systemctl is-active --quiet containerd; then
                success "Containerd configured and running with NVIDIA support"
            else
                error "Containerd failed to start with NVIDIA configuration"
                warning "Restoring backup configuration..."
                
                # Restore backup if available
                BACKUP_FILE=$(ls -t /etc/containerd/config.toml.backup.* 2>/dev/null | head -1)
                if [ -n "$BACKUP_FILE" ]; then
                    cp "$BACKUP_FILE" /etc/containerd/config.toml
                    systemctl restart containerd
                    warning "Restored backup configuration, NVIDIA runtime not configured"
                else
                    # Generate clean config
                    containerd config default > /etc/containerd/config.toml
                    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
                    systemctl restart containerd
                    warning "Generated clean configuration, NVIDIA runtime not configured"
                fi
                
                if systemctl is-active --quiet containerd; then
                    warning "Containerd restored but without NVIDIA support"
                    warning "You may need to configure NVIDIA runtime manually after reboot"
                else
                    error "Failed to restore containerd"
                    exit 1
                fi
            fi
        else
            error "NVIDIA runtime configuration is invalid"
            warning "Restoring backup configuration..."
            
            # Restore backup
            BACKUP_FILE=$(ls -t /etc/containerd/config.toml.backup.* 2>/dev/null | head -1)
            if [ -n "$BACKUP_FILE" ]; then
                cp "$BACKUP_FILE" /etc/containerd/config.toml
            else
                containerd config default > /etc/containerd/config.toml
                sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
            fi
            
            systemctl restart containerd
            warning "NVIDIA runtime configuration failed, using basic configuration"
        fi
    else
        error "Failed to configure NVIDIA runtime"
        warning "Continuing with basic containerd configuration"
    fi
    
    # Final verification
    systemctl enable containerd
    
    if systemctl is-active --quiet containerd; then
        success "Containerd is running and enabled for autostart"
    else
        error "Containerd is not running properly"
        exit 1
    fi
}

# Install NVIDIA Device Plugin for Kubernetes
install_device_plugin() {
    if [ "$K8S_AVAILABLE" = false ]; then
        warning "Kubernetes not available, skipping device plugin installation"
        info "To install the device plugin later, use the following manifest:"
        info "kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/$NVIDIA_DEVICE_PLUGIN_VERSION/nvidia-device-plugin.yml"
        return
    fi
    
    log "Installing NVIDIA Device Plugin for Kubernetes..."
    
    # Create NVIDIA device plugin manifest
    cat <<EOF > /tmp/nvidia-device-plugin.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: nvidia-device-plugin-daemonset
  namespace: kube-system
spec:
  selector:
    matchLabels:
      name: nvidia-device-plugin-ds
  updateStrategy:
    type: RollingUpdate
  template:
    metadata:
      labels:
        name: nvidia-device-plugin-ds
    spec:
      tolerations:
      - key: nvidia.com/gpu
        operator: Exists
        effect: NoSchedule
      priorityClassName: "system-node-critical"
      containers:
      - image: nvcr.io/nvidia/k8s-device-plugin:$NVIDIA_DEVICE_PLUGIN_VERSION
        name: nvidia-device-plugin-ctr
        args: ["--fail-on-init-error=false"]
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
        volumeMounts:
          - name: device-plugin
            mountPath: /var/lib/kubelet/device-plugins
      volumes:
        - name: device-plugin
          hostPath:
            path: /var/lib/kubelet/device-plugins
      nodeSelector:
        kubernetes.io/arch: amd64
EOF

    # Apply the device plugin with better error handling
    log "Applying NVIDIA Device Plugin manifest..."
    if kubectl apply -f /tmp/nvidia-device-plugin.yaml --validate=false; then
        success "NVIDIA Device Plugin installed successfully"
    else
        error "Failed to install NVIDIA Device Plugin"
        warning "This might be due to:"
        warning "1. Insufficient permissions"
        warning "2. Network connectivity issues"
        warning "3. Kubernetes API server not accessible from this node"
        echo ""
        info "Manual installation options:"
        info "1. Copy the manifest to a machine with kubectl access:"
        info "   scp /tmp/nvidia-device-plugin.yaml <control-plane>:/tmp/"
        info "2. Apply from control plane:"
        info "   kubectl apply -f /tmp/nvidia-device-plugin.yaml"
        info "3. Or use the official manifest:"
        info "   kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/$NVIDIA_DEVICE_PLUGIN_VERSION/nvidia-device-plugin.yml"
        echo ""
        warning "Continuing with installation - device plugin can be installed later"
    fi
    
    # Keep the manifest file for manual installation
    if [ -f /tmp/nvidia-device-plugin.yaml ]; then
        cp /tmp/nvidia-device-plugin.yaml /root/nvidia-device-plugin.yaml
        info "Device plugin manifest saved to: /root/nvidia-device-plugin.yaml"
        rm -f /tmp/nvidia-device-plugin.yaml
    fi
}

# Create test GPU workload
create_test_workload() {
    if [ "$K8S_AVAILABLE" = false ]; then
        warning "Kubernetes not available, skipping test workload creation"
        info "To create a test workload later, use:"
        info "kubectl apply -f - <<EOF"
        info "apiVersion: v1"
        info "kind: Pod"
        info "metadata:"
        info "  name: gpu-test"
        info "spec:"
        info "  restartPolicy: Never"
        info "  containers:"
        info "  - name: gpu-test"
        info "    image: nvidia/cuda:12.2-runtime-ubuntu20.04"
        info "    command: [\"nvidia-smi\"]"
        info "    resources:"
        info "      limits:"
        info "        nvidia.com/gpu: 1"
        info "EOF"
        return
    fi
    
    echo ""
    echo -n "Do you want to create a test GPU workload? (y/N): "
    read -r CREATE_TEST
    
    if [[ $CREATE_TEST =~ ^[Yy]$ ]]; then
        log "Creating test GPU workload..."
        
        cat <<EOF > /tmp/gpu-test.yaml
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

        if kubectl apply -f /tmp/gpu-test.yaml --validate=false; then
            success "Test GPU workload created"
            info "Check the test with: kubectl logs gpu-test"
            info "Clean up with: kubectl delete pod gpu-test"
        else
            warning "Failed to create test workload - kubectl connectivity issues"
            info "Test workload manifest saved to: /tmp/gpu-test.yaml"
            info "Apply manually from a machine with cluster access"
        fi
        
        rm -f /tmp/gpu-test.yaml
    fi
}

# Verify installation
verify_installation() {
    log "Verifying NVIDIA installation..."
    
    # Check if reboot is required
    if [ -f /var/run/reboot-required ]; then
        warning "System reboot is required to complete driver installation"
        REBOOT_REQUIRED=true
    else
        REBOOT_REQUIRED=false
    fi
    
    # Test NVIDIA driver
    echo ""
    info "Testing NVIDIA driver..."
    if command -v nvidia-smi &> /dev/null; then
        if nvidia-smi &> /dev/null; then
            nvidia-smi
            success "NVIDIA driver is working correctly"
            DRIVER_WORKING=true
        else
            warning "nvidia-smi command failed - driver may not be loaded"
            warning "This usually indicates a reboot is required"
            REBOOT_REQUIRED=true
            DRIVER_WORKING=false
        fi
    else
        warning "nvidia-smi not available - driver installation may be incomplete"
        REBOOT_REQUIRED=true
        DRIVER_WORKING=false
    fi
    
    # Check if driver modules are loaded
    if lsmod | grep -q nvidia; then
        success "NVIDIA kernel modules are loaded"
    else
        warning "NVIDIA kernel modules are not loaded - reboot required"
        REBOOT_REQUIRED=true
    fi
    
    # Check containerd configuration
    echo ""
    info "Containerd status:"
    systemctl status containerd --no-pager -l
    
    # Check Kubernetes device plugin (if available and driver is working)
    if [ "$K8S_AVAILABLE" = true ] && [ "$DRIVER_WORKING" = true ]; then
        echo ""
        info "NVIDIA Device Plugin status:"
        if kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds 2>/dev/null; then
            echo ""
            info "Node GPU capacity:"
            kubectl describe nodes | grep -A 5 "Capacity:" | grep nvidia.com/gpu || echo "GPU capacity not yet available"
        else
            warning "Cannot check device plugin status - kubectl connectivity issues"
        fi
    elif [ "$K8S_AVAILABLE" = true ] && [ "$DRIVER_WORKING" = false ]; then
        warning "Skipping Kubernetes GPU checks - driver not working yet"
        info "After reboot, check device plugin with:"
        info "kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds"
    fi
}

# Display post-installation information
display_post_install_info() {
    echo ""
    success "NVIDIA GPU drivers installation completed!"
    echo ""
    echo "=============================================="
    echo "NVIDIA INSTALLATION SUMMARY"
    echo "=============================================="
    echo "• NVIDIA Driver: $NVIDIA_DRIVER_VERSION series"
    
    # Get actual installed version of container toolkit
    CONTAINER_TOOLKIT_VERSION=$(dpkg -l | grep nvidia-container-toolkit | awk '{print $3}' | head -1 || echo "Unknown")
    echo "• Container Toolkit: $CONTAINER_TOOLKIT_VERSION"
    
    echo "• Device Plugin: $NVIDIA_DEVICE_PLUGIN_VERSION"
    echo "• Containerd: Configured for GPU support"
    
    if [ "$K8S_AVAILABLE" = true ]; then
        echo "• Kubernetes: Device plugin installation attempted"
    else
        echo "• Kubernetes: Device plugin installation skipped (no cluster access)"
    fi
    
    echo ""
    echo "Verification commands:"
    echo "• Check driver: nvidia-smi"
    echo "• Test container: docker run --rm --gpus all nvidia/cuda:12.2-runtime-ubuntu20.04 nvidia-smi"
    
    if [ "$K8S_AVAILABLE" = true ]; then
        echo "• Check K8s GPUs: kubectl describe nodes | grep nvidia.com/gpu"
        echo "• View device plugin: kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds"
    fi
    
    echo ""
    if [ "$REBOOT_REQUIRED" = true ]; then
        highlight "⚠️  REBOOT REQUIRED"
        highlight "Please reboot the system to complete the installation:"
        highlight "sudo reboot"
        echo ""
        warning "After reboot, verify with: nvidia-smi"
        warning "Or run the verification script: sudo /root/verify-nvidia-post-reboot.sh"
        
        if [ "$K8S_AVAILABLE" = false ]; then
            echo ""
            warning "Kubernetes Device Plugin Installation:"
            warning "Since kubectl couldn't connect to the cluster, install the device plugin manually:"
            warning "1. From a machine with cluster access (control plane):"
            warning "   kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/$NVIDIA_DEVICE_PLUGIN_VERSION/nvidia-device-plugin.yml"
            warning "2. Or copy the saved manifest:"
            warning "   scp root@$(hostname):/root/nvidia-device-plugin.yaml /tmp/"
            warning "   kubectl apply -f /tmp/nvidia-device-plugin.yaml"
        fi
    else
        success "✅ Installation complete - no reboot required"
        
        if [ "$K8S_AVAILABLE" = false ]; then
            echo ""
            warning "Kubernetes Device Plugin Installation:"
            warning "Install the device plugin from a machine with cluster access:"
            warning "kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/$NVIDIA_DEVICE_PLUGIN_VERSION/nvidia-device-plugin.yml"
        fi
    fi
    
    echo ""
    echo "GPU Workload Example:"
    echo "apiVersion: v1"
    echo "kind: Pod"
    echo "metadata:"
    echo "  name: gpu-pod"
    echo "spec:"
    echo "  containers:"
    echo "  - name: gpu-container"
    echo "    image: nvidia/cuda:12.2-runtime-ubuntu20.04"
    echo "    command: ['nvidia-smi']"
    echo "    resources:"
    echo "      limits:"
    echo "        nvidia.com/gpu: 1"
    echo ""
    warning "Remember to:"
    warning "1. Ensure your workloads request GPU resources"
    warning "2. Use NVIDIA-compatible container images"
    warning "3. Monitor GPU usage with nvidia-smi"
    
    if [ -f /root/nvidia-device-plugin.yaml ]; then
        echo ""
        info "Device plugin manifest saved to: /root/nvidia-device-plugin.yaml"
        info "Use this file for manual installation if needed"
    fi
}

# Create post-reboot script
create_post_reboot_script() {
    if [ "$REBOOT_REQUIRED" = true ]; then
        log "Creating post-reboot verification script..."
        
        cat <<'EOF' > /root/verify-nvidia-post-reboot.sh
#!/bin/bash

# Post-reboot NVIDIA verification script
# Run this script after rebooting to verify the installation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }

echo "=============================================="
echo "POST-REBOOT NVIDIA VERIFICATION"
echo "=============================================="

# Check and fix containerd first
log "Checking containerd service..."
if systemctl is-active --quiet containerd; then
    success "containerd is running"
else
    warning "containerd is not running, attempting to start..."
    systemctl start containerd
    sleep 10
    
    if systemctl is-active --quiet containerd; then
        success "containerd started successfully"
    else
        error "Failed to start containerd"
        error "Attempting to fix containerd configuration..."
        
        # Backup current config and regenerate
        if [ -f /etc/containerd/config.toml ]; then
            cp /etc/containerd/config.toml /etc/containerd/config.toml.broken.$(date +%s)
        fi
        
        # Generate clean config
        containerd config default > /etc/containerd/config.toml
        sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
        
        systemctl start containerd
        sleep 10
        
        if systemctl is-active --quiet containerd; then
            warning "containerd fixed with basic configuration"
            warning "NVIDIA runtime may need to be reconfigured"
        else
            error "Failed to fix containerd - manual intervention required"
            exit 1
        fi
    fi
fi

# Check and fix kubelet
log "Checking kubelet service..."
if systemctl is-active --quiet kubelet; then
    success "kubelet is running"
else
    warning "kubelet is not running, attempting to start..."
    
    # Clean up any corrupted state
    if [ -f /var/lib/kubelet/config.yaml ]; then
        mv /var/lib/kubelet/config.yaml /var/lib/kubelet/config.yaml.backup.$(date +%s)
    fi
    
    systemctl start kubelet
    sleep 15
    
    if systemctl is-active --quiet kubelet; then
        success "kubelet started successfully"
    else
        warning "kubelet failed to start - this may be normal and it will retry"
        info "Check kubelet logs: journalctl -u kubelet -f"
    fi
fi

# Test NVIDIA driver
log "Testing NVIDIA driver..."
if nvidia-smi; then
    success "NVIDIA driver is working correctly!"
    NVIDIA_WORKING=true
else
    error "NVIDIA driver is still not working"
    error "You may need to:"
    error "1. Check if secure boot is disabled"
    error "2. Reinstall the driver"
    error "3. Check kernel compatibility"
    NVIDIA_WORKING=false
fi

# Check kernel modules
log "Checking NVIDIA kernel modules..."
if lsmod | grep nvidia; then
    success "NVIDIA kernel modules are loaded"
else
    error "NVIDIA kernel modules are not loaded"
    if [ "$NVIDIA_WORKING" = false ]; then
        error "This confirms the NVIDIA driver issue"
    fi
fi

# Test container runtime (if NVIDIA is working)
if [ "$NVIDIA_WORKING" = true ]; then
    log "Testing NVIDIA container runtime..."
    if command -v docker &> /dev/null; then
        if docker run --rm --gpus all nvidia/cuda:12.2-runtime-ubuntu20.04 nvidia-smi; then
            success "NVIDIA container runtime is working!"
        else
            warning "NVIDIA container runtime test failed"
            warning "You may need to restart Docker: sudo systemctl restart docker"
            warning "Or reconfigure containerd NVIDIA runtime"
        fi
    else
        info "Docker not available for testing"
        info "Test with containerd: ctr run --rm --gpus all docker.io/nvidia/cuda:12.2-runtime-ubuntu20.04 test nvidia-smi"
    fi
fi

# Check Kubernetes device plugin (if manifest exists)
if [ -f /root/nvidia-device-plugin.yaml ]; then
    echo ""
    warning "Kubernetes Device Plugin Installation:"
    warning "The device plugin manifest is available at: /root/nvidia-device-plugin.yaml"
    warning "Install it from a machine with cluster access:"
    warning "kubectl apply -f /root/nvidia-device-plugin.yaml"
    echo ""
    warning "Or use the official manifest:"
    warning "kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.16.2/nvidia-device-plugin.yml"
fi

echo ""
if [ "$NVIDIA_WORKING" = true ]; then
    success "✅ Post-reboot verification completed!"
    success "Your NVIDIA GPU setup is ready for use."
    echo ""
    info "Next steps:"
    info "1. Install the Kubernetes device plugin (see above)"
    info "2. Test GPU workloads in Kubernetes"
    info "3. Monitor GPU usage with: nvidia-smi"
else
    error "❌ NVIDIA driver verification failed"
    error "The system is accessible but NVIDIA drivers need attention"
    echo ""
    info "Recovery options:"
    info "1. Check secure boot: mokutil --sb-state"
    info "2. Reinstall drivers: sudo apt install --reinstall nvidia-driver-550"
    info "3. Check for kernel updates: sudo apt update && sudo apt upgrade"
    info "4. Verify GPU hardware: lspci | grep -i nvidia"
fi

echo ""
info "System status:"
systemctl is-active --quiet containerd && echo "✅ containerd: running" || echo "❌ containerd: not running"
systemctl is-active --quiet kubelet && echo "✅ kubelet: running" || echo "⚠️  kubelet: not running (may be starting)"
systemctl is-active --quiet ssh && echo "✅ SSH: running" || echo "❌ SSH: not running"
EOF

        chmod +x /root/verify-nvidia-post-reboot.sh
        success "Post-reboot script created: /root/verify-nvidia-post-reboot.sh"
        info "Run this script after reboot: sudo /root/verify-nvidia-post-reboot.sh"
    fi
}

# Main installation function
main() {
    echo ""
    echo "=============================================="
    echo "NVIDIA GPU DRIVERS INSTALLATION"
    echo "=============================================="
    echo ""
    
    log "Starting NVIDIA GPU drivers installation..."
    
    # Pre-flight checks
    check_root
    check_os
    detect_nvidia_gpu
    check_kubernetes
    
    # Installation process
    cleanup_existing
    install_prerequisites
    install_nvidia_drivers
    install_container_toolkit
    configure_containerd
    install_device_plugin
    create_test_workload
    
    # Verification and information
    verify_installation
    display_post_install_info
    create_post_reboot_script
}

# Run main function
main "$@" 