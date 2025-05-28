#!/bin/bash

# Storage Extension Script for Kubernetes Worker Nodes
# This script automatically extends the root partition and filesystem to use all available disk space
# Compatible with Ubuntu 20.04+ systems using LVM

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

# Detect the main disk and partition layout
detect_disk_layout() {
    log "Detecting disk layout..."
    
    # Find the root filesystem device
    ROOT_DEVICE=$(df / | tail -1 | awk '{print $1}')
    info "Root filesystem device: $ROOT_DEVICE"
    
    # Check if it's an LVM device
    if [[ $ROOT_DEVICE == /dev/mapper/* ]]; then
        LVM_DETECTED=true
        info "LVM detected: $ROOT_DEVICE"
        
        # Get VG and LV names
        VG_NAME=$(lvdisplay "$ROOT_DEVICE" | grep "VG Name" | awk '{print $3}')
        LV_NAME=$(lvdisplay "$ROOT_DEVICE" | grep "LV Name" | awk '{print $3}')
        
        info "Volume Group: $VG_NAME"
        info "Logical Volume: $LV_NAME"
        
        # Find the physical volume
        PV_DEVICE=$(pvdisplay | grep -B1 "$VG_NAME" | grep "PV Name" | awk '{print $3}')
        info "Physical Volume: $PV_DEVICE"
        
        # Extract the base disk from PV device (e.g., /dev/sda3 -> /dev/sda)
        if [[ $PV_DEVICE =~ ^(/dev/[a-z]+)[0-9]+$ ]]; then
            DISK_DEVICE="${BASH_REMATCH[1]}"
            PARTITION_NUMBER="${PV_DEVICE##*[a-z]}"
        else
            error "Cannot determine disk device from $PV_DEVICE"
            exit 1
        fi
        
    else
        LVM_DETECTED=false
        warning "LVM not detected. This script is designed for LVM setups."
        warning "For non-LVM setups, manual intervention may be required."
        
        # Try to determine disk from root device
        if [[ $ROOT_DEVICE =~ ^(/dev/[a-z]+)[0-9]+$ ]]; then
            DISK_DEVICE="${BASH_REMATCH[1]}"
            PARTITION_NUMBER="${ROOT_DEVICE##*[a-z]}"
            PV_DEVICE="$ROOT_DEVICE"
        else
            error "Cannot determine disk device from $ROOT_DEVICE"
            exit 1
        fi
    fi
    
    info "Target disk: $DISK_DEVICE"
    info "Target partition: $PV_DEVICE (partition $PARTITION_NUMBER)"
}

# Check current disk usage and available space
check_disk_space() {
    log "Checking current disk space..."
    
    # Show current filesystem usage
    echo ""
    info "Current filesystem usage:"
    df -h / | grep -E "(Filesystem|$ROOT_DEVICE)"
    
    # Show current disk layout
    echo ""
    info "Current disk layout:"
    fdisk -l "$DISK_DEVICE" | grep -E "(Disk $DISK_DEVICE|Device.*Start.*End|$DISK_DEVICE[0-9])"
    
    # Calculate available space
    TOTAL_SECTORS=$(fdisk -l "$DISK_DEVICE" | grep "^Disk $DISK_DEVICE" | awk '{print $7}')
    CURRENT_END=$(fdisk -l "$DISK_DEVICE" | grep "$PV_DEVICE" | awk '{print $3}')
    AVAILABLE_SECTORS=$((TOTAL_SECTORS - CURRENT_END - 1))
    AVAILABLE_GB=$((AVAILABLE_SECTORS * 512 / 1024 / 1024 / 1024))
    
    info "Total disk sectors: $TOTAL_SECTORS"
    info "Current partition end: $CURRENT_END"
    info "Available sectors: $AVAILABLE_SECTORS"
    info "Available space: ~${AVAILABLE_GB}GB"
    
    if [ "$AVAILABLE_SECTORS" -lt 1000000 ]; then
        warning "Less than ~500MB available space detected"
        warning "Extension may not provide significant benefit"
        echo -n "Continue anyway? (y/N): "
        read -r CONTINUE
        if [[ ! $CONTINUE =~ ^[Yy]$ ]]; then
            info "Operation cancelled by user"
            exit 0
        fi
    fi
}

# Backup partition table
backup_partition_table() {
    log "Creating partition table backup..."
    
    BACKUP_DIR="/root/storage-extension-backup-$(date +%s)"
    mkdir -p "$BACKUP_DIR"
    
    # Backup partition table
    sfdisk -d "$DISK_DEVICE" > "$BACKUP_DIR/partition-table.sfdisk"
    
    # Backup LVM configuration if applicable
    if [ "$LVM_DETECTED" = true ]; then
        vgcfgbackup -f "$BACKUP_DIR/lvm-backup" "$VG_NAME" 2>/dev/null || true
    fi
    
    # Save current filesystem info
    df -h > "$BACKUP_DIR/filesystem-before.txt"
    lsblk > "$BACKUP_DIR/lsblk-before.txt"
    
    success "Backup created in: $BACKUP_DIR"
    info "Restore command (if needed): sfdisk $DISK_DEVICE < $BACKUP_DIR/partition-table.sfdisk"
}

# Extend the partition using fdisk
extend_partition() {
    log "Extending partition $PV_DEVICE..."
    
    # Get current partition info
    PARTITION_START=$(fdisk -l "$DISK_DEVICE" | grep "$PV_DEVICE" | awk '{print $2}')
    PARTITION_TYPE=$(fdisk -l "$DISK_DEVICE" | grep "$PV_DEVICE" | awk '{print $6}')
    
    info "Current partition start: $PARTITION_START"
    info "Current partition type: $PARTITION_TYPE"
    
    # Use fdisk to delete and recreate the partition
    log "Recreating partition to use all available space..."
    
    # Create fdisk commands
    FDISK_COMMANDS="d
$PARTITION_NUMBER
n
$PARTITION_NUMBER
$PARTITION_START

t
$PARTITION_NUMBER
8e
w"

    # Execute fdisk commands
    echo "$FDISK_COMMANDS" | fdisk "$DISK_DEVICE" || {
        error "Failed to extend partition with fdisk"
        error "You may need to restore from backup: $BACKUP_DIR"
        exit 1
    }
    
    success "Partition extended successfully"
    
    # Refresh partition table
    log "Refreshing partition table..."
    partprobe "$DISK_DEVICE" || {
        warning "partprobe failed, trying alternative methods..."
        blockdev --rereadpt "$DISK_DEVICE" || {
            warning "blockdev failed too, continuing anyway..."
        }
    }
    
    sleep 2
}

# Extend LVM components
extend_lvm() {
    if [ "$LVM_DETECTED" = false ]; then
        warning "LVM not detected, skipping LVM extension"
        return
    fi
    
    log "Extending LVM components..."
    
    # Resize physical volume
    log "Resizing physical volume: $PV_DEVICE"
    if ! pvresize "$PV_DEVICE"; then
        error "Failed to resize physical volume"
        exit 1
    fi
    success "Physical volume resized"
    
    # Extend logical volume
    log "Extending logical volume: $ROOT_DEVICE"
    if ! lvextend -l +100%FREE "$ROOT_DEVICE"; then
        error "Failed to extend logical volume"
        exit 1
    fi
    success "Logical volume extended"
}

# Extend the filesystem
extend_filesystem() {
    log "Extending filesystem..."
    
    # Detect filesystem type
    FS_TYPE=$(blkid -o value -s TYPE "$ROOT_DEVICE")
    info "Filesystem type: $FS_TYPE"
    
    case "$FS_TYPE" in
        ext2|ext3|ext4)
            log "Extending ext filesystem..."
            if ! resize2fs "$ROOT_DEVICE"; then
                error "Failed to extend ext filesystem"
                exit 1
            fi
            ;;
        xfs)
            log "Extending XFS filesystem..."
            if ! xfs_growfs /; then
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
    
    success "Filesystem extended successfully"
}

# Verify the extension
verify_extension() {
    log "Verifying storage extension..."
    
    echo ""
    info "New filesystem usage:"
    df -h / | grep -E "(Filesystem|$ROOT_DEVICE)"
    
    echo ""
    info "New disk layout:"
    fdisk -l "$DISK_DEVICE" | grep -E "(Disk $DISK_DEVICE|Device.*Start.*End|$DISK_DEVICE[0-9])"
    
    if [ "$LVM_DETECTED" = true ]; then
        echo ""
        info "LVM status:"
        pvdisplay "$PV_DEVICE" | grep -E "(PV Name|VG Name|PV Size)"
        lvdisplay "$ROOT_DEVICE" | grep -E "(LV Name|VG Name|LV Size)"
    fi
    
    # Check if containerd directory has more space
    echo ""
    info "Containerd storage space:"
    df -h /var/lib/containerd 2>/dev/null || df -h /var/lib/
    
    # Save post-extension info
    if [ -n "$BACKUP_DIR" ]; then
        df -h > "$BACKUP_DIR/filesystem-after.txt"
        lsblk > "$BACKUP_DIR/lsblk-after.txt"
        info "Post-extension info saved to: $BACKUP_DIR"
    fi
}

# Check for Kubernetes services and restart if needed
restart_k8s_services() {
    log "Checking Kubernetes services..."
    
    # Check if kubelet is running
    if systemctl is-active --quiet kubelet; then
        info "Kubelet is running"
        
        # Check if containerd needs restart (sometimes needed after storage changes)
        if systemctl is-active --quiet containerd; then
            log "Restarting containerd to ensure proper operation..."
            systemctl restart containerd
            sleep 10
            
            if systemctl is-active --quiet containerd; then
                success "Containerd restarted successfully"
            else
                warning "Containerd failed to restart"
            fi
        fi
        
        # Restart kubelet to ensure it recognizes new storage
        log "Restarting kubelet to recognize new storage..."
        systemctl restart kubelet
        sleep 15
        
        if systemctl is-active --quiet kubelet; then
            success "Kubelet restarted successfully"
        else
            warning "Kubelet failed to restart - check logs: journalctl -u kubelet -f"
        fi
    else
        info "Kubelet not running - no restart needed"
    fi
}

# Display summary and recommendations
display_summary() {
    echo ""
    success "Storage extension completed successfully!"
    echo ""
    echo "=============================================="
    echo "STORAGE EXTENSION SUMMARY"
    echo "=============================================="
    
    # Calculate space gained
    if [ -f "$BACKUP_DIR/filesystem-before.txt" ]; then
        BEFORE_AVAIL=$(grep "$ROOT_DEVICE" "$BACKUP_DIR/filesystem-before.txt" | awk '{print $4}' || echo "Unknown")
        AFTER_AVAIL=$(df -h / | grep "$ROOT_DEVICE" | awk '{print $4}')
        echo "• Available space before: $BEFORE_AVAIL"
        echo "• Available space after: $AFTER_AVAIL"
    fi
    
    echo "• Target disk: $DISK_DEVICE"
    echo "• Extended partition: $PV_DEVICE"
    
    if [ "$LVM_DETECTED" = true ]; then
        echo "• LVM Volume Group: $VG_NAME"
        echo "• LVM Logical Volume: $LV_NAME"
    fi
    
    echo "• Filesystem type: $(blkid -o value -s TYPE "$ROOT_DEVICE")"
    echo ""
    
    highlight "✅ Your Kubernetes worker node now has more storage space!"
    echo ""
    
    info "Verification commands:"
    info "• Check disk usage: df -h /"
    info "• Check disk layout: lsblk"
    info "• Check containerd space: df -h /var/lib/containerd"
    
    if [ "$LVM_DETECTED" = true ]; then
        info "• Check LVM: pvdisplay && lvdisplay"
    fi
    
    echo ""
    info "Backup location: $BACKUP_DIR"
    info "Keep this backup until you're sure everything works correctly"
    
    echo ""
    warning "Recommendations:"
    warning "1. Monitor disk usage regularly: df -h"
    warning "2. Set up disk usage alerts if needed"
    warning "3. Consider log rotation for container logs"
    warning "4. Clean up unused container images: docker system prune"
    
    if systemctl is-active --quiet kubelet; then
        echo ""
        success "Kubernetes services are running normally"
        info "Your cluster should continue operating without issues"
    fi
}

# Main function
main() {
    echo ""
    echo "=============================================="
    echo "KUBERNETES STORAGE EXTENSION"
    echo "=============================================="
    echo ""
    
    log "Starting storage extension process..."
    
    # Safety checks
    check_root
    detect_disk_layout
    check_disk_space
    
    # Confirm before proceeding
    echo ""
    warning "⚠️  This operation will modify disk partitions!"
    warning "Make sure you have backups of important data"
    echo ""
    echo -n "Proceed with storage extension? (y/N): "
    read -r PROCEED
    
    if [[ ! $PROCEED =~ ^[Yy]$ ]]; then
        info "Operation cancelled by user"
        exit 0
    fi
    
    # Perform extension
    backup_partition_table
    extend_partition
    extend_lvm
    extend_filesystem
    verify_extension
    restart_k8s_services
    display_summary
}

# Run main function
main "$@" 