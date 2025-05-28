#!/bin/bash

# NVIDIA Driver Fix Script
# This script diagnoses and fixes NVIDIA driver issues after installation

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

# Comprehensive NVIDIA diagnosis
diagnose_nvidia() {
    log "Performing comprehensive NVIDIA diagnosis..."
    
    echo ""
    info "=== GPU HARDWARE DETECTION ==="
    if lspci | grep -i nvidia; then
        success "NVIDIA GPU hardware detected"
        GPU_DETECTED=true
    else
        error "No NVIDIA GPU hardware found"
        GPU_DETECTED=false
        return 1
    fi
    
    echo ""
    info "=== SECURE BOOT STATUS ==="
    if command -v mokutil &> /dev/null; then
        SECURE_BOOT_STATUS=$(mokutil --sb-state 2>/dev/null || echo "unknown")
        info "Secure Boot: $SECURE_BOOT_STATUS"
        if echo "$SECURE_BOOT_STATUS" | grep -q "SecureBoot enabled"; then
            warning "Secure Boot is ENABLED - this often prevents NVIDIA drivers from loading"
            SECURE_BOOT_ENABLED=true
        else
            success "Secure Boot is disabled or not supported"
            SECURE_BOOT_ENABLED=false
        fi
    else
        info "mokutil not available, cannot check Secure Boot status"
        SECURE_BOOT_ENABLED=false
    fi
    
    echo ""
    info "=== KERNEL AND DRIVER COMPATIBILITY ==="
    KERNEL_VERSION=$(uname -r)
    info "Current kernel: $KERNEL_VERSION"
    
    # Check if kernel headers are installed
    if dpkg -l | grep -q "linux-headers-$KERNEL_VERSION"; then
        success "Kernel headers for current kernel are installed"
        HEADERS_INSTALLED=true
    else
        error "Kernel headers for current kernel are NOT installed"
        HEADERS_INSTALLED=false
    fi
    
    # Check NVIDIA driver packages
    echo ""
    info "=== NVIDIA DRIVER PACKAGES ==="
    if dpkg -l | grep -q nvidia-driver; then
        success "NVIDIA driver packages are installed:"
        dpkg -l | grep nvidia-driver | awk '{print "  " $2 " " $3}'
        DRIVER_PACKAGES_INSTALLED=true
    else
        error "No NVIDIA driver packages found"
        DRIVER_PACKAGES_INSTALLED=false
    fi
    
    # Check DKMS status
    echo ""
    info "=== DKMS STATUS ==="
    if command -v dkms &> /dev/null; then
        info "DKMS modules:"
        dkms status | grep nvidia || info "No NVIDIA DKMS modules found"
        
        # Check if NVIDIA modules are built for current kernel
        if dkms status | grep -q "nvidia.*$KERNEL_VERSION.*installed"; then
            success "NVIDIA DKMS modules are built for current kernel"
            DKMS_BUILT=true
        else
            warning "NVIDIA DKMS modules are NOT built for current kernel"
            DKMS_BUILT=false
        fi
    else
        warning "DKMS not available"
        DKMS_BUILT=false
    fi
    
    # Check kernel modules
    echo ""
    info "=== KERNEL MODULES ==="
    if lsmod | grep -q nvidia; then
        success "NVIDIA kernel modules are loaded:"
        lsmod | grep nvidia
        MODULES_LOADED=true
    else
        error "NVIDIA kernel modules are NOT loaded"
        MODULES_LOADED=false
    fi
    
    # Check if modules exist
    NVIDIA_MODULE_PATH="/lib/modules/$KERNEL_VERSION/updates/dkms"
    if [ -d "$NVIDIA_MODULE_PATH" ] && find "$NVIDIA_MODULE_PATH" -name "nvidia*.ko" | grep -q .; then
        success "NVIDIA kernel module files exist for current kernel"
        MODULE_FILES_EXIST=true
    else
        error "NVIDIA kernel module files do NOT exist for current kernel"
        MODULE_FILES_EXIST=false
    fi
}

# Fix kernel headers
fix_kernel_headers() {
    if [ "$HEADERS_INSTALLED" = false ]; then
        log "Installing kernel headers for current kernel..."
        apt-get update -y
        apt-get install -y linux-headers-$(uname -r)
        
        if dpkg -l | grep -q "linux-headers-$(uname -r)"; then
            success "Kernel headers installed successfully"
            HEADERS_INSTALLED=true
        else
            error "Failed to install kernel headers"
            return 1
        fi
    fi
}

# Rebuild NVIDIA DKMS modules
rebuild_nvidia_dkms() {
    log "Rebuilding NVIDIA DKMS modules..."
    
    # Remove existing NVIDIA DKMS modules
    if dkms status | grep -q nvidia; then
        log "Removing existing NVIDIA DKMS modules..."
        for module in $(dkms status | grep nvidia | cut -d',' -f1 | sort -u); do
            dkms remove "$module" --all || true
        done
    fi
    
    # Find NVIDIA driver version
    NVIDIA_VERSION=$(dpkg -l | grep nvidia-driver | head -1 | awk '{print $3}' | cut -d'-' -f1)
    if [ -z "$NVIDIA_VERSION" ]; then
        NVIDIA_VERSION="550"  # Default fallback
    fi
    
    log "Detected NVIDIA driver version: $NVIDIA_VERSION"
    
    # Add and build NVIDIA DKMS module
    if [ -d "/usr/src/nvidia-$NVIDIA_VERSION" ]; then
        log "Adding NVIDIA DKMS module..."
        dkms add -m nvidia -v "$NVIDIA_VERSION"
        
        log "Building NVIDIA DKMS module for kernel $(uname -r)..."
        if dkms build -m nvidia -v "$NVIDIA_VERSION" -k "$(uname -r)"; then
            success "NVIDIA DKMS module built successfully"
            
            log "Installing NVIDIA DKMS module..."
            if dkms install -m nvidia -v "$NVIDIA_VERSION" -k "$(uname -r)"; then
                success "NVIDIA DKMS module installed successfully"
                DKMS_BUILT=true
                MODULE_FILES_EXIST=true
            else
                error "Failed to install NVIDIA DKMS module"
                return 1
            fi
        else
            error "Failed to build NVIDIA DKMS module"
            return 1
        fi
    else
        error "NVIDIA source directory not found: /usr/src/nvidia-$NVIDIA_VERSION"
        return 1
    fi
}

# Load NVIDIA kernel modules
load_nvidia_modules() {
    log "Loading NVIDIA kernel modules..."
    
    # Load modules in correct order
    local modules=("nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm")
    
    for module in "${modules[@]}"; do
        if ! lsmod | grep -q "^$module"; then
            log "Loading module: $module"
            if modprobe "$module"; then
                success "Module $module loaded successfully"
            else
                warning "Failed to load module: $module (may not be required)"
            fi
        else
            info "Module $module already loaded"
        fi
    done
    
    # Check if nvidia module is loaded
    if lsmod | grep -q "^nvidia"; then
        success "NVIDIA kernel modules loaded successfully"
        MODULES_LOADED=true
    else
        error "Failed to load NVIDIA kernel modules"
        return 1
    fi
}

# Reinstall NVIDIA drivers
reinstall_nvidia_drivers() {
    log "Reinstalling NVIDIA drivers..."
    
    # Remove existing NVIDIA packages
    log "Removing existing NVIDIA packages..."
    apt-get remove --purge -y nvidia-* libnvidia-* || true
    apt-get autoremove -y || true
    
    # Clean up any remaining files
    rm -rf /usr/lib/nvidia* || true
    rm -rf /usr/lib32/nvidia* || true
    
    # Update package index
    apt-get update -y
    
    # Install NVIDIA driver
    log "Installing NVIDIA driver 550..."
    if apt-get install -y nvidia-driver-550; then
        success "NVIDIA driver installed successfully"
        
        # Install additional packages
        apt-get install -y nvidia-settings nvidia-prime || true
        
        DRIVER_PACKAGES_INSTALLED=true
    else
        error "Failed to install NVIDIA driver"
        return 1
    fi
}

# Configure NVIDIA for persistence
configure_nvidia_persistence() {
    log "Configuring NVIDIA persistence..."
    
    # Create nvidia-persistenced service if it doesn't exist
    if ! systemctl list-unit-files | grep -q nvidia-persistenced; then
        log "Creating NVIDIA persistence service..."
        
        cat <<'EOF' > /etc/systemd/system/nvidia-persistenced.service
[Unit]
Description=NVIDIA Persistence Daemon
Wants=syslog.target

[Service]
Type=forking
PIDFile=/var/run/nvidia-persistenced/nvidia-persistenced.pid
Restart=always
ExecStart=/usr/bin/nvidia-persistenced --verbose
ExecStopPost=/bin/rm -rf /var/run/nvidia-persistenced

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl daemon-reload
        systemctl enable nvidia-persistenced
    fi
    
    # Set up module loading at boot
    echo "nvidia" > /etc/modules-load.d/nvidia.conf
    echo "nvidia_modeset" >> /etc/modules-load.d/nvidia.conf
    echo "nvidia_uvm" >> /etc/modules-load.d/nvidia.conf
    echo "nvidia_drm" >> /etc/modules-load.d/nvidia.conf
    
    success "NVIDIA persistence configured"
}

# Test NVIDIA functionality
test_nvidia() {
    log "Testing NVIDIA functionality..."
    
    if nvidia-smi; then
        success "nvidia-smi is working!"
        
        # Test NVIDIA device files
        if [ -c /dev/nvidia0 ]; then
            success "NVIDIA device files exist"
        else
            warning "NVIDIA device files missing"
        fi
        
        return 0
    else
        error "nvidia-smi still not working"
        return 1
    fi
}

# Display fix summary
display_fix_summary() {
    echo ""
    success "NVIDIA driver fix process completed!"
    echo ""
    echo "=============================================="
    echo "FIX SUMMARY"
    echo "=============================================="
    
    # Test final status
    if nvidia-smi &> /dev/null; then
        echo "✅ NVIDIA Driver: WORKING"
        echo "✅ nvidia-smi: FUNCTIONAL"
        
        if lsmod | grep -q nvidia; then
            echo "✅ Kernel Modules: LOADED"
        fi
        
        echo ""
        success "🎉 NVIDIA drivers are now working correctly!"
        echo ""
        info "Next steps:"
        info "1. Configure containerd NVIDIA runtime: nvidia-ctk runtime configure --runtime=containerd"
        info "2. Restart containerd: systemctl restart containerd"
        info "3. Install Kubernetes device plugin from control plane"
        info "4. Test GPU workloads"
        
    else
        echo "❌ NVIDIA Driver: STILL NOT WORKING"
        echo ""
        error "The fix process completed but NVIDIA is still not working"
        echo ""
        info "Additional troubleshooting needed:"
        info "1. Check dmesg for NVIDIA errors: dmesg | grep -i nvidia"
        info "2. Check if GPU is properly seated in PCIe slot"
        info "3. Verify power connections to GPU"
        info "4. Check BIOS settings (disable Secure Boot, enable PCIe)"
        info "5. Consider different driver version"
        
        if [ "$SECURE_BOOT_ENABLED" = true ]; then
            echo ""
            highlight "⚠️  SECURE BOOT IS ENABLED"
            highlight "This is likely preventing NVIDIA drivers from loading"
            highlight "Disable Secure Boot in BIOS/UEFI settings and reboot"
        fi
    fi
}

# Main fix function
main() {
    echo ""
    echo "=============================================="
    echo "NVIDIA DRIVER FIX SCRIPT"
    echo "=============================================="
    echo ""
    
    log "Starting NVIDIA driver fix process..."
    
    # Check if running as root
    check_root
    
    # Diagnose current state
    diagnose_nvidia
    
    if [ "$GPU_DETECTED" = false ]; then
        error "No NVIDIA GPU detected - cannot proceed"
        exit 1
    fi
    
    # Apply fixes based on diagnosis
    if [ "$SECURE_BOOT_ENABLED" = true ]; then
        error "Secure Boot is enabled - this must be disabled in BIOS first"
        error "Please disable Secure Boot and reboot, then run this script again"
        exit 1
    fi
    
    # Fix kernel headers if needed
    if [ "$HEADERS_INSTALLED" = false ]; then
        fix_kernel_headers
    fi
    
    # If driver packages are missing, reinstall
    if [ "$DRIVER_PACKAGES_INSTALLED" = false ]; then
        reinstall_nvidia_drivers
    fi
    
    # If DKMS modules are not built, rebuild them
    if [ "$DKMS_BUILT" = false ] || [ "$MODULE_FILES_EXIST" = false ]; then
        rebuild_nvidia_dkms
    fi
    
    # If modules are not loaded, load them
    if [ "$MODULES_LOADED" = false ]; then
        load_nvidia_modules
    fi
    
    # Configure persistence
    configure_nvidia_persistence
    
    # Test functionality
    test_nvidia
    
    # Display summary
    display_fix_summary
}

# Run main function
main "$@" 