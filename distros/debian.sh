#!/bin/bash

install_debian() {
    print_step "Installing Debian ${SELECTED_VERSION}..."
    
    source "${LIB_DIR}/partition.sh"
    source "${LIB_DIR}/network.sh"
    source "${LIB_DIR}/common.sh"
    
    local codename
    case "$SELECTED_VERSION" in
        12) codename="bookworm" ;;
        11) codename="bullseye" ;;
        *) die "Unsupported Debian version: ${SELECTED_VERSION}" ;;
    esac
    
    print_info "Debian codename: ${codename}"
    
    print_step "Installing required packages..."
    apt-get update -qq
    apt-get install -y -qq debootstrap debian-keyring debian-archive-keyring \
        squashfs-tools e2fsprogs parted gdisk dosfstools
    
    partition_disk "$INSTALL_DISK" "$BOOT_MODE"
    mount_partitions "$INSTALL_DISK" "$BOOT_MODE"
    save_network_config "$MOUNT_ROOT"
    
    print_step "Bootstrapping Debian base system..."
    print_info "This may take 10-20 minutes depending on network speed..."
    
    debootstrap --arch=amd64 --variant=minbase "$codename" "$MOUNT_ROOT" http://deb.debian.org/debian/
    
    print_success "Base system installed"
    
    print_step "Configuring APT sources..."
    cat > "${MOUNT_ROOT}/etc/apt/sources.list" << EOF
deb http://deb.debian.org/debian ${codename} main contrib non-free-firmware
deb http://deb.debian.org/debian ${codename}-updates main contrib non-free-firmware
deb http://security.debian.org/debian-security ${codename}-security main contrib non-free-firmware
EOF
    
    setup_chroot "$MOUNT_ROOT"
    
    print_step "Installing kernel and essential packages..."
    run_chroot "$MOUNT_ROOT" "apt-get update -qq"
    run_chroot "$MOUNT_ROOT" "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        linux-image-amd64 \
        linux-headers-amd64 \
        grub-efi-amd64 \
        grub-pc \
        openssh-server \
        sudo \
        systemd \
        systemd-sysv \
        locales \
        tzdata \
        ifupdown \
        isc-dhcp-client \
        iproute2 \
        --no-install-recommends"
    
    print_step "Configuring locale..."
    run_chroot "$MOUNT_ROOT" "sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen"
    run_chroot "$MOUNT_ROOT" "locale-gen en_US.UTF-8"
    echo "LANG=en_US.UTF-8" > "${MOUNT_ROOT}/etc/default/locale"
    
    print_step "Configuring timezone..."
    run_chroot "$MOUNT_ROOT" "ln -sf /usr/share/zoneinfo/UTC /etc/localtime"
    
    set_hostname "$MOUNT_ROOT" "$HOSTNAME"
    create_user "$MOUNT_ROOT" "$USERNAME" "$PASSWORD"
    
    configure_network_interfaces "$MOUNT_ROOT" "$PRIMARY_INTERFACE"
    configure_ssh "$MOUNT_ROOT" "$SSH_PORT" "$SSH_KEY" "$USERNAME"
    configure_fstab "$MOUNT_ROOT" "$INSTALL_DISK" "$BOOT_MODE"
    install_grub "$MOUNT_ROOT" "$INSTALL_DISK" "$BOOT_MODE"
    
    print_step "Enabling services..."
    run_chroot "$MOUNT_ROOT" "systemctl enable ssh"
    
    cleanup_chroot "$MOUNT_ROOT"
    unmount_partitions
    
    print_success "Debian ${SELECTED_VERSION} installation complete!"
    print_info "System will reboot into your new Debian installation."
}
