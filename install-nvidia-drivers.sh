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
NVIDIA_CONTAINER_TOOLKIT_VERSION="1.16.2"
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
    
    success "Kubernetes detected and running"
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
    
    # Install NVIDIA Container Toolkit
    apt-get install -y nvidia-container-toolkit=$NVIDIA_CONTAINER_TOOLKIT_VERSION-1
    
    success "NVIDIA Container Toolkit installed"
}

# Configure containerd for NVIDIA
configure_containerd() {
    log "Configuring containerd for NVIDIA support..."
    
    # Generate default containerd config if it doesn't exist
    if [ ! -f /etc/containerd/config.toml ]; then
        mkdir -p /etc/containerd
        containerd config default > /etc/containerd/config.toml
    fi
    
    # Configure NVIDIA runtime
    nvidia-ctk runtime configure --runtime=containerd
    
    # Restart containerd
    systemctl restart containerd
    systemctl enable containerd
    
    # Verify containerd is running
    if systemctl is-active --quiet containerd; then
        success "Containerd configured and running with NVIDIA support"
    else
        error "Failed to restart containerd"
        exit 1
    fi
}

# Install NVIDIA Device Plugin for Kubernetes
install_device_plugin() {
    if [ "$K8S_AVAILABLE" = false ]; then
        warning "Kubernetes not available, skipping device plugin installation"
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

    # Apply the device plugin
    kubectl apply -f /tmp/nvidia-device-plugin.yaml
    
    # Clean up temp file
    rm -f /tmp/nvidia-device-plugin.yaml
    
    success "NVIDIA Device Plugin installed"
}

# Create test GPU workload
create_test_workload() {
    if [ "$K8S_AVAILABLE" = false ]; then
        warning "Kubernetes not available, skipping test workload creation"
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

        kubectl apply -f /tmp/gpu-test.yaml
        rm -f /tmp/gpu-test.yaml
        
        success "Test GPU workload created"
        info "Check the test with: kubectl logs gpu-test"
        info "Clean up with: kubectl delete pod gpu-test"
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
    
    # Test NVIDIA driver (if not reboot required)
    if [ "$REBOOT_REQUIRED" = false ]; then
        echo ""
        info "Testing NVIDIA driver..."
        if command -v nvidia-smi &> /dev/null; then
            nvidia-smi
            success "NVIDIA driver is working"
        else
            warning "nvidia-smi not available yet - may require reboot"
        fi
    fi
    
    # Check containerd configuration
    echo ""
    info "Containerd status:"
    systemctl status containerd --no-pager -l
    
    # Check Kubernetes device plugin (if available)
    if [ "$K8S_AVAILABLE" = true ]; then
        echo ""
        info "NVIDIA Device Plugin status:"
        kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds
        
        echo ""
        info "Node GPU capacity:"
        kubectl describe nodes | grep -A 5 "Capacity:" | grep nvidia.com/gpu || echo "GPU capacity not yet available"
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
    echo "• Container Toolkit: $NVIDIA_CONTAINER_TOOLKIT_VERSION"
    echo "• Device Plugin: $NVIDIA_DEVICE_PLUGIN_VERSION"
    echo "• Containerd: Configured for GPU support"
    
    if [ "$K8S_AVAILABLE" = true ]; then
        echo "• Kubernetes: Device plugin installed"
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
    else
        success "✅ Installation complete - no reboot required"
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
}

# Run main function
main "$@" 