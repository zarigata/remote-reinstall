#!/bin/bash

install_ubuntu() {
    print_step "Installing Ubuntu ${SELECTED_VERSION}..."
    
    source "${LIB_DIR}/partition.sh"
    source "${LIB_DIR}/network.sh"
    source "${LIB_DIR}/common.sh"
    
    local codename
    case "$SELECTED_VERSION" in
        24.04) codename="noble" ;;
        22.04) codename="jammy" ;;
        20.04) codename="focal" ;;
        *) die "Unsupported Ubuntu version: ${SELECTED_VERSION}" ;;
    esac
    
    print_info "Ubuntu codename: ${codename}"
    
    print_step "Installing required packages..."
    apt-get update -qq
    apt-get install -y -qq debootstrap ubuntu-keyring squashfs-tools e2fsprogs parted gdisk
    
    partition_disk "$INSTALL_DISK" "$BOOT_MODE"
    mount_partitions "$INSTALL_DISK" "$BOOT_MODE"
    save_network_config "$MOUNT_ROOT"
    
    print_step "Bootstrapping Ubuntu base system..."
    print_info "This may take 10-20 minutes depending on network speed..."
    
    debootstrap --arch=amd64 --variant=minbase "$codename" "$MOUNT_ROOT" http://archive.ubuntu.com/ubuntu/
    
    print_success "Base system installed"
    
    print_step "Configuring APT sources..."
    cat > "${MOUNT_ROOT}/etc/apt/sources.list" << EOF
deb http://archive.ubuntu.com/ubuntu ${codename} main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu ${codename}-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu ${codename}-security main restricted universe multiverse
EOF
    
    setup_chroot "$MOUNT_ROOT"
    
    print_step "Installing kernel and essential packages..."
    run_chroot "$MOUNT_ROOT" "apt-get update -qq"
    run_chroot "$MOUNT_ROOT" "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        linux-generic \
        linux-headers-generic \
        grub-efi-amd64 \
        grub-pc \
        openssh-server \
        sudo \
        cloud-init \
        netplan.io \
        systemd-resolved \
        systemd-sysv \
        locales \
        tzdata \
        kbd \
        console-setup \
        --no-install-recommends"
    
    print_step "Configuring locale..."
    run_chroot "$MOUNT_ROOT" "locale-gen en_US.UTF-8"
    echo "LANG=en_US.UTF-8" > "${MOUNT_ROOT}/etc/default/locale"
    
    print_step "Configuring timezone..."
    run_chroot "$MOUNT_ROOT" "ln -sf /usr/share/zoneinfo/UTC /etc/localtime"
    
    set_hostname "$MOUNT_ROOT" "$HOSTNAME"
    create_user "$MOUNT_ROOT" "$USERNAME" "$PASSWORD"
    
    print_step "Configuring network with Netplan..."
    mkdir -p "${MOUNT_ROOT}/etc/netplan"
    cat > "${MOUNT_ROOT}/etc/netplan/01-netcfg.yaml" << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${PRIMARY_INTERFACE}:
      addresses:
        - ${PRIMARY_IP}/24
      routes:
        - to: default
          via: $(ip route | grep default | awk '{print $3}')
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
EOF
    chmod 600 "${MOUNT_ROOT}/etc/netplan/01-netcfg.yaml"
    
    configure_ssh "$MOUNT_ROOT" "$SSH_PORT" "$SSH_KEY" "$USERNAME"
    configure_fstab "$MOUNT_ROOT" "$INSTALL_DISK" "$BOOT_MODE"
    install_grub "$MOUNT_ROOT" "$INSTALL_DISK" "$BOOT_MODE"
    
    print_step "Enabling services..."
    run_chroot "$MOUNT_ROOT" "systemctl enable ssh"
    run_chroot "$MOUNT_ROOT" "systemctl enable systemd-networkd"
    run_chroot "$MOUNT_ROOT" "systemctl enable systemd-resolved"
    
    cleanup_chroot "$MOUNT_ROOT"
    unmount_partitions
    
    print_success "Ubuntu ${SELECTED_VERSION} installation complete!"
    print_info "System will reboot into your new Ubuntu installation."
}
