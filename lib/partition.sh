#!/bin/bash

partition_disk() {
    local disk="$1"
    local boot_mode="$2"
    
    print_step "Partitioning disk: ${disk}"
    print_warning "This will erase ALL data on ${disk}"
    
    wipefs -a "$disk" 2>/dev/null || true
    sgdisk --zap-all "$disk" 2>/dev/null || true
    
    if [[ "$boot_mode" == "UEFI" ]]; then
        print_info "Creating UEFI partition layout..."
        parted -s "$disk" mklabel gpt
        parted -s "$disk" mkpart ESP fat32 1MiB 513MiB
        parted -s "$disk" set 1 esp on
        parted -s "$disk" mkpart primary ext4 513MiB 100%
        PART_BOOT="${disk}1"
        PART_ROOT="${disk}2"
    else
        print_info "Creating BIOS partition layout..."
        parted -s "$disk" mklabel msdos
        parted -s "$disk" mkpart primary ext4 1MiB 100%
        parted -s "$disk" set 1 boot on
        PART_BOOT=""
        PART_ROOT="${disk}1"
    fi
    
    sleep 2
    
    if [[ -n "$PART_BOOT" ]]; then
        mkfs.vfat -F32 "$PART_BOOT"
        print_success "Created boot partition: ${PART_BOOT}"
    fi
    
    mkfs.ext4 -F "$PART_ROOT"
    print_success "Created root partition: ${PART_ROOT}"
    
    echo "$PART_ROOT" > /tmp/remote-reinstall-part-root
    [[ -n "$PART_BOOT" ]] && echo "$PART_BOOT" > /tmp/remote-reinstall-part-boot
}

mount_partitions() {
    local disk="$1"
    local boot_mode="$2"
    
    print_step "Mounting partitions..."
    
    PART_ROOT=$(cat /tmp/remote-reinstall-part-root 2>/dev/null || echo "${disk}1")
    PART_BOOT=$(cat /tmp/remote-reinstall-part-boot 2>/dev/null || echo "")
    
    export MOUNT_ROOT="/mnt/target"
    mkdir -p "$MOUNT_ROOT"
    mount "$PART_ROOT" "$MOUNT_ROOT"
    
    if [[ "$boot_mode" == "UEFI" ]]; then
        mkdir -p "${MOUNT_ROOT}/boot/efi"
        [[ -n "$PART_BOOT" ]] && mount "$PART_BOOT" "${MOUNT_ROOT}/boot/efi"
    else
        mkdir -p "${MOUNT_ROOT}/boot"
    fi
    
    print_success "Partitions mounted at ${MOUNT_ROOT}"
}

unmount_partitions() {
    print_step "Unmounting partitions..."
    
    if mountpoint -q "${MOUNT_ROOT}/boot/efi" 2>/dev/null; then
        umount "${MOUNT_ROOT}/boot/efi" 2>/dev/null || true
    fi
    if mountpoint -q "${MOUNT_ROOT}/boot" 2>/dev/null; then
        umount "${MOUNT_ROOT}/boot" 2>/dev/null || true
    fi
    if mountpoint -q "${MOUNT_ROOT}/proc" 2>/dev/null; then
        umount "${MOUNT_ROOT}/proc" 2>/dev/null || true
    fi
    if mountpoint -q "${MOUNT_ROOT}/sys" 2>/dev/null; then
        umount "${MOUNT_ROOT}/sys" 2>/dev/null || true
    fi
    if mountpoint -q "${MOUNT_ROOT}/dev" 2>/dev/null; then
        umount "${MOUNT_ROOT}/dev" 2>/dev/null || true
    fi
    if mountpoint -q "${MOUNT_ROOT}" 2>/dev/null; then
        umount "${MOUNT_ROOT}" 2>/dev/null || true
    fi
    
    print_success "Partitions unmounted"
}
