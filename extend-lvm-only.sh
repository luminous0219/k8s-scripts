#!/bin/bash

# LVM-Only Extension Script for Kubernetes Worker Nodes
# This script extends LVM logical volumes when partition is already correct size
# but LV hasn't been extended to use all available PV space

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

# Detect LVM layout
detect_lvm_layout() {
    log "Detecting LVM layout..."
    
    # Find the root filesystem device
    ROOT_DEVICE=$(df / | tail -1 | awk '{print $1}')
    info "Root filesystem device: $ROOT_DEVICE"
    
    # Check if it's an LVM device
    if [[ $ROOT_DEVICE != /dev/mapper/* ]]; then
        error "This script is designed for LVM setups only"
        error "Your root device ($ROOT_DEVICE) is not an LVM device"
        exit 1
    fi
    
    # Get VG and LV names
    VG_NAME=$(lvdisplay "$ROOT_DEVICE" | grep "VG Name" | awk '{print $3}')
    LV_NAME=$(lvdisplay "$ROOT_DEVICE" | grep "LV Name" | awk '{print $3}')
    
    info "Volume Group: $VG_NAME"
    info "Logical Volume: $LV_NAME"
    
    # Find the physical volume
    PV_DEVICE=$(pvdisplay | grep -B1 "$VG_NAME" | grep "PV Name" | awk '{print $3}')
    info "Physical Volume: $PV_DEVICE"
}

# Check available space in VG
check_vg_space() {
    log "Checking Volume Group free space..."
    
    # Get VG information
    VG_SIZE=$(vgdisplay "$VG_NAME" | grep "VG Size" | awk '{print $3 $4}')
    VG_FREE=$(vgdisplay "$VG_NAME" | grep "Free" | awk '{print $7 $8}')
    
    info "Volume Group Size: $VG_SIZE"
    info "Volume Group Free Space: $VG_FREE"
    
    # Get LV information
    LV_SIZE=$(lvdisplay "$ROOT_DEVICE" | grep "LV Size" | awk '{print $3 $4}')
    info "Current Logical Volume Size: $LV_SIZE"
    
    # Check if there's free space
    FREE_EXTENTS=$(vgdisplay "$VG_NAME" | grep "Free" | awk '{print $5}')
    if [ "$FREE_EXTENTS" -eq 0 ]; then
        warning "No free space available in Volume Group"
        warning "The Volume Group is already fully allocated"
        echo ""
        info "This usually means:"
        info "1. The partition needs to be extended first, OR"
        info "2. The physical volume needs to be resized"
        echo ""
        echo -n "Do you want to try resizing the physical volume first? (y/N): "
        read -r RESIZE_PV
        
        if [[ $RESIZE_PV =~ ^[Yy]$ ]]; then
            RESIZE_PV_FIRST=true
        else
            info "Operation cancelled - no free space to extend"
            exit 0
        fi
    else
        info "Free extents available: $FREE_EXTENTS"
        RESIZE_PV_FIRST=false
    fi
}

# Show current status
show_current_status() {
    echo ""
    info "Current storage status:"
    echo ""
    
    # Filesystem usage
    info "Filesystem usage:"
    df -h / | grep -E "(Filesystem|$ROOT_DEVICE)"
    
    echo ""
    info "LVM status:"
    echo "Physical Volume:"
    pvdisplay "$PV_DEVICE" | grep -E "(PV Name|VG Name|PV Size|Allocatable|PE Size|Total PE|Free PE)"
    
    echo ""
    echo "Volume Group:"
    vgdisplay "$VG_NAME" | grep -E "(VG Name|VG Size|PE Size|Total PE|Alloc PE|Free PE)"
    
    echo ""
    echo "Logical Volume:"
    lvdisplay "$ROOT_DEVICE" | grep -E "(LV Name|VG Name|LV Size|Current LE)"
}

# Resize physical volume if needed
resize_physical_volume() {
    if [ "$RESIZE_PV_FIRST" = true ]; then
        log "Resizing physical volume: $PV_DEVICE"
        
        if pvresize "$PV_DEVICE"; then
            success "Physical volume resized successfully"
            
            # Check VG space again
            VG_FREE_AFTER=$(vgdisplay "$VG_NAME" | grep "Free" | awk '{print $7 $8}')
            FREE_EXTENTS_AFTER=$(vgdisplay "$VG_NAME" | grep "Free" | awk '{print $5}')
            
            info "Volume Group Free Space after PV resize: $VG_FREE_AFTER"
            info "Free extents after PV resize: $FREE_EXTENTS_AFTER"
            
            if [ "$FREE_EXTENTS_AFTER" -eq 0 ]; then
                error "Still no free space after PV resize"
                error "The partition may need to be extended first"
                exit 1
            fi
        else
            error "Failed to resize physical volume"
            exit 1
        fi
    fi
}

# Extend logical volume
extend_logical_volume() {
    log "Extending logical volume to use all free space..."
    
    # Show what will happen
    FREE_EXTENTS=$(vgdisplay "$VG_NAME" | grep "Free" | awk '{print $5}')
    info "Will extend logical volume by $FREE_EXTENTS free extents"
    
    if lvextend -l +100%FREE "$ROOT_DEVICE"; then
        success "Logical volume extended successfully"
    else
        error "Failed to extend logical volume"
        exit 1
    fi
}

# Extend filesystem
extend_filesystem() {
    log "Extending filesystem to use new logical volume space..."
    
    # Detect filesystem type
    FS_TYPE=$(blkid -o value -s TYPE "$ROOT_DEVICE")
    info "Filesystem type: $FS_TYPE"
    
    case "$FS_TYPE" in
        ext2|ext3|ext4)
            log "Extending ext filesystem..."
            if resize2fs "$ROOT_DEVICE"; then
                success "Ext filesystem extended successfully"
            else
                error "Failed to extend ext filesystem"
                exit 1
            fi
            ;;
        xfs)
            log "Extending XFS filesystem..."
            if xfs_growfs /; then
                success "XFS filesystem extended successfully"
            else
                error "Failed to extend XFS filesystem"
                exit 1
            fi
            ;;
        *)
            error "Unsupported filesystem type: $FS_TYPE"
            error "Manual filesystem extension required"
            exit 1
            ;;
    esac
}

# Restart services
restart_services() {
    log "Restarting Kubernetes services..."
    
    # Check if kubelet is running
    if systemctl is-active --quiet kubelet; then
        info "Restarting containerd..."
        systemctl restart containerd
        sleep 5
        
        info "Restarting kubelet..."
        systemctl restart kubelet
        sleep 10
        
        if systemctl is-active --quiet kubelet && systemctl is-active --quiet containerd; then
            success "Kubernetes services restarted successfully"
        else
            warning "Some services may not have restarted properly"
        fi
    else
        info "Kubelet not running - no restart needed"
    fi
}

# Show final status
show_final_status() {
    echo ""
    success "LVM extension completed!"
    echo ""
    echo "=============================================="
    echo "FINAL STORAGE STATUS"
    echo "=============================================="
    
    # Filesystem usage
    info "New filesystem usage:"
    df -h / | grep -E "(Filesystem|$ROOT_DEVICE)"
    
    echo ""
    info "Final LVM status:"
    echo "Physical Volume:"
    pvdisplay "$PV_DEVICE" | grep -E "(PV Name|VG Name|PV Size|Allocatable|PE Size|Total PE|Free PE)"
    
    echo ""
    echo "Volume Group:"
    vgdisplay "$VG_NAME" | grep -E "(VG Name|VG Size|PE Size|Total PE|Alloc PE|Free PE)"
    
    echo ""
    echo "Logical Volume:"
    lvdisplay "$ROOT_DEVICE" | grep -E "(LV Name|VG Name|LV Size|Current LE)"
    
    echo ""
    highlight "✅ Your storage has been extended successfully!"
    
    # Calculate space gained
    NEW_SIZE=$(df -h / | grep "$ROOT_DEVICE" | awk '{print $2}')
    NEW_AVAIL=$(df -h / | grep "$ROOT_DEVICE" | awk '{print $4}')
    
    echo ""
    info "Storage summary:"
    info "• Total filesystem size: $NEW_SIZE"
    info "• Available space: $NEW_AVAIL"
    info "• Containerd storage: $(df -h /var/lib/containerd 2>/dev/null | tail -1 | awk '{print $4}' || echo 'Same as root')"
    
    echo ""
    warning "Verification commands:"
    warning "• Check disk usage: df -h /"
    warning "• Check LVM status: pvdisplay && vgdisplay && lvdisplay"
    warning "• Check services: systemctl status kubelet containerd"
}

# Main function
main() {
    echo ""
    echo "=============================================="
    echo "LVM LOGICAL VOLUME EXTENSION"
    echo "=============================================="
    echo ""
    
    log "Starting LVM extension process..."
    
    # Checks
    check_root
    detect_lvm_layout
    check_vg_space
    show_current_status
    
    # Confirm
    echo ""
    warning "⚠️  This will extend your logical volume to use all available space"
    echo ""
    echo -n "Proceed with LVM extension? (y/N): "
    read -r PROCEED
    
    if [[ ! $PROCEED =~ ^[Yy]$ ]]; then
        info "Operation cancelled by user"
        exit 0
    fi
    
    # Perform extension
    resize_physical_volume
    extend_logical_volume
    extend_filesystem
    restart_services
    show_final_status
}

# Run main function
main "$@" 