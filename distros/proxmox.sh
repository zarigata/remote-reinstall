#!/bin/bash

install_proxmox() {
    print_step "Installing Proxmox VE ${SELECTED_VERSION}..."
    
    source "${LIB_DIR}/partition.sh"
    source "${LIB_DIR}/network.sh"
    source "${LIB_DIR}/common.sh"
    
    local codename
    local debian_codename
    case "$SELECTED_VERSION" in
        8)
            codename="bookworm"
            debian_codename="bookworm"
            pve_repo="bookworm"
            ;;
        7)
            codename="bullseye"
            debian_codename="bullseye"
            pve_repo="bullseye"
            ;;
        *) die "Unsupported Proxmox version: ${SELECTED_VERSION}" ;;
    esac
    
    print_info "Base: Debian ${debian_codename}"
    
    print_step "Installing required packages..."
    apt-get update -qq
    apt-get install -y -qq debootstrap debian-keyring debian-archive-keyring \
        squashfs-tools e2fsprogs parted gdisk dosfstools gnupg2
    
    partition_disk "$INSTALL_DISK" "$BOOT_MODE"
    mount_partitions "$INSTALL_DISK" "$BOOT_MODE"
    save_network_config "$MOUNT_ROOT"
    
    print_step "Bootstrapping Debian base system for Proxmox..."
    print_info "This may take 10-20 minutes depending on network speed..."
    
    debootstrap --arch=amd64 --variant=minbase "$debian_codename" "$MOUNT_ROOT" http://deb.debian.org/debian/
    
    print_success "Base system installed"
    
    print_step "Configuring APT sources with Proxmox repositories..."
    cat > "${MOUNT_ROOT}/etc/apt/sources.list" << EOF
deb http://deb.debian.org/debian ${debian_codename} main contrib non-free-firmware
deb http://deb.debian.org/debian ${debian_codename}-updates main contrib non-free-firmware
deb http://security.debian.org/debian-security ${debian_codename}-security main contrib non-free-firmware

deb [arch=amd64] http://download.proxmox.com/debian/pve ${pve_repo} pve-no-subscription
deb [arch=amd64] http://download.proxmox.com/debian/ceph-quincy ${pve_repo} no-subscription
EOF
    
    setup_chroot "$MOUNT_ROOT"
    
    print_step "Installing kernel and essential packages..."
    run_chroot "$MOUNT_ROOT" "apt-get update -qq"
    run_chroot "$MOUNT_ROOT" "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        linux-image-amd64 \
        grub-efi-amd64 \
        grub-pc \
        openssh-server \
        sudo \
        locales \
        tzdata \
        curl \
        wget \
        gnupg2 \
        --no-install-recommends"
    
    print_step "Adding Proxmox GPG key..."
    run_chroot "$MOUNT_ROOT" "curl -fsSL https://enterprise.proxmox.com/debian/proxmox-release-${pve_repo}.gpg -o /etc/apt/trusted.gpg.d/proxmox-release-${pve_repo}.gpg"
    
    print_step "Updating package lists with Proxmox repos..."
    run_chroot "$MOUNT_ROOT" "apt-get update -qq"
    
    print_step "Installing Proxmox VE packages..."
    print_info "This may take 20-40 minutes..."
    run_chroot "$MOUNT_ROOT" "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        proxmox-ve \
        postfix \
        open-iscsi \
        --no-install-recommends" || {
        print_warning "Some Proxmox packages may have failed, continuing..."
    }
    
    print_step "Configuring locale..."
    run_chroot "$MOUNT_ROOT" "sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen"
    run_chroot "$MOUNT_ROOT" "locale-gen en_US.UTF-8"
    echo "LANG=en_US.UTF-8" > "${MOUNT_ROOT}/etc/default/locale"
    
    print_step "Configuring timezone..."
    run_chroot "$MOUNT_ROOT" "ln -sf /usr/share/zoneinfo/UTC /etc/localtime"
    
    set_hostname "$MOUNT_ROOT" "$HOSTNAME"
    create_user "$MOUNT_ROOT" "$USERNAME" "$PASSWORD"
    
    print_step "Configuring Proxmox admin user..."
    run_chroot "$MOUNT_ROOT" "usermod -aG root ${USERNAME}" 2>/dev/null || true
    
    print_step "Configuring network for Proxmox..."
    mkdir -p "${MOUNT_ROOT}/etc/network"
    cat > "${MOUNT_ROOT}/etc/network/interfaces" << EOF
auto lo
iface lo inet loopback

auto ${PRIMARY_INTERFACE}
iface ${PRIMARY_INTERFACE} inet static
    address ${PRIMARY_IP}/24
    gateway $(ip route | grep default | awk '{print $3}')
    dns-nameservers 8.8.8.8 8.8.4.4
EOF
    
    cat > "${MOUNT_ROOT}/etc/hosts" << EOF
127.0.0.1 localhost.localdomain localhost
${PRIMARY_IP} ${HOSTNAME}.localdomain ${HOSTNAME}

::1 localhost.localdomain localhost ip6-localhost ip6-loopback
EOF
    
    configure_ssh "$MOUNT_ROOT" "$SSH_PORT" "$SSH_KEY" "$USERNAME"
    configure_fstab "$MOUNT_ROOT" "$INSTALL_DISK" "$BOOT_MODE"
    install_grub "$MOUNT_ROOT" "$INSTALL_DISK" "$BOOT_MODE"
    
    print_step "Enabling services..."
    run_chroot "$MOUNT_ROOT" "systemctl enable ssh"
    run_chroot "$MOUNT_ROOT" "systemctl enable pveproxy" 2>/dev/null || true
    run_chroot "$MOUNT_ROOT" "systemctl enable pvedaemon" 2>/dev/null || true
    run_chroot "$MOUNT_ROOT" "systemctl enable pvestatd" 2>/dev/null || true
    
    cleanup_chroot "$MOUNT_ROOT"
    unmount_partitions
    
    print_success "Proxmox VE ${SELECTED_VERSION} installation complete!"
    print_info "Web interface will be available at: https://${PRIMARY_IP}:8006"
    print_info "System will reboot into your new Proxmox installation."
}
