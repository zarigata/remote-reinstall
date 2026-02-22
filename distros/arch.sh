#!/bin/bash

install_arch() {
    print_step "Installing Arch Linux..."
    
    source "${LIB_DIR}/partition.sh"
    source "${LIB_DIR}/network.sh"
    source "${LIB_DIR}/common.sh"
    
    print_step "Installing required packages..."
    pacman -Sy --noconfirm parted e2fsprogs dosfstools util-linux
    
    partition_disk "$INSTALL_DISK" "$BOOT_MODE"
    mount_partitions "$INSTALL_DISK" "$BOOT_MODE"
    save_network_config "$MOUNT_ROOT"
    
    print_step "Installing Arch Linux base system using pacstrap..."
    print_info "This may take 15-30 minutes depending on network speed..."
    
    pacstrap -K "$MOUNT_ROOT" base base-devel linux linux-firmware \
        grub efibootmgr \
        openssh sudo \
        systemd systemd-sysvcompat \
        networkmanager \
        vim nano \
        bash bash-completion \
        coreutils \
        util-linux \
        shadow \
        procps-ng \
        psmisc \
        iproute2 \
        iputils \
        dhcpcd
    
    print_success "Base system installed"
    
    print_step "Configuring Arch Linux..."
    
    echo "${HOSTNAME}" > "${MOUNT_ROOT}/etc/hostname"
    
    cat > "${MOUNT_ROOT}/etc/hosts" << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF
    
    print_step "Configuring locale..."
    echo "en_US.UTF-8 UTF-8" >> "${MOUNT_ROOT}/etc/locale.gen"
    echo "LANG=en_US.UTF-8" > "${MOUNT_ROOT}/etc/locale.conf"
    
    print_step "Configuring vconsole..."
    echo "KEYMAP=us" > "${MOUNT_ROOT}/etc/vconsole.conf"
    
    print_step "Configuring pacman..."
    cat > "${MOUNT_ROOT}/etc/pacman.conf" << EOF
[options]
HoldPkg     = pacman glibc
Architecture = auto
CheckSpace
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[community]
Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
    
    print_step "Generating mirrorlist..."
    mkdir -p "${MOUNT_ROOT}/etc/pacman.d"
    cat > "${MOUNT_ROOT}/etc/pacman.d/mirrorlist" << 'EOF'
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch
Server = https://mirror.leaseweb.net/archlinux/$repo/os/$arch
Server = https://arch.mirror.constant.com/$repo/os/$arch
Server = https://mirror.pkgbuild.com/$repo/os/$arch
EOF
    
    setup_chroot "$MOUNT_ROOT"
    
    print_step "Generating locale..."
    run_chroot "$MOUNT_ROOT" "locale-gen"
    
    print_step "Creating user..."
    run_chroot "$MOUNT_ROOT" "useradd -m -s /bin/bash -G wheel ${USERNAME}"
    echo "${USERNAME}:${PASSWORD}" | run_chroot "$MOUNT_ROOT" "chpasswd"
    
    print_step "Configuring sudo..."
    run_chroot "$MOUNT_ROOT" "sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers"
    
    print_step "Setting root password..."
    echo "root:${PASSWORD}" | run_chroot "$MOUNT_ROOT" "chpasswd"
    
    configure_network_nm "$MOUNT_ROOT" "$PRIMARY_INTERFACE"
    configure_ssh "$MOUNT_ROOT" "$SSH_PORT" "$SSH_KEY" "$USERNAME"
    configure_fstab "$MOUNT_ROOT" "$INSTALL_DISK" "$BOOT_MODE"
    install_grub "$MOUNT_ROOT" "$INSTALL_DISK" "$BOOT_MODE"
    
    print_step "Creating initramfs..."
    run_chroot "$MOUNT_ROOT" "mkinitcpio -P"
    
    print_step "Enabling services..."
    run_chroot "$MOUNT_ROOT" "systemctl enable sshd"
    run_chroot "$MOUNT_ROOT" "systemctl enable NetworkManager"
    
    cleanup_chroot "$MOUNT_ROOT"
    unmount_partitions
    
    print_success "Arch Linux installation complete!"
    print_info "System will reboot into your new Arch Linux installation."
}
