#!/bin/bash

install_rocky() {
    print_step "Installing Rocky Linux ${SELECTED_VERSION}..."
    
    source "${LIB_DIR}/partition.sh"
    source "${LIB_DIR}/network.sh"
    source "${LIB_DIR}/common.sh"
    
    print_step "Installing required packages..."
    dnf install -y dnf-plugins-core parted e2fsprogs dosfstools util-linux
    
    partition_disk "$INSTALL_DISK" "$BOOT_MODE"
    mount_partitions "$INSTALL_DISK" "$BOOT_MODE"
    save_network_config "$MOUNT_ROOT"
    
    print_step "Installing Rocky Linux base system using DNF..."
    print_info "This may take 15-30 minutes depending on network speed..."
    
    dnf --installroot="$MOUNT_ROOT" \
        --releasever="${SELECTED_VERSION}" \
        install -y \
        @core \
        kernel \
        grub2-efi-x64 \
        grub2-pc \
        shim-x64 \
        openssh-server \
        sudo \
        systemd \
        systemd-udev \
        passwd \
        shadow-utils \
        util-linux \
        NetworkManager \
        firewalld \
        chrony \
        langpacks-en \
        --nogpgcheck \
        --releasever="${SELECTED_VERSION}"
    
    print_success "Base system installed"
    
    print_step "Configuring repositories..."
    mkdir -p "${MOUNT_ROOT}/etc/yum.repos.d"
    
    if [[ "$SELECTED_VERSION" == "9" ]]; then
        cat > "${MOUNT_ROOT}/etc/yum.repos.d/rocky.repo" << EOF
[baseos]
name=Rocky Linux ${SELECTED_VERSION} - BaseOS
mirrorlist=https://mirrors.rockylinux.org/mirrorlist?arch=x86_64&repo=BaseOS-${SELECTED_VERSION}
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-rocky-${SELECTED_VERSION}

[appstream]
name=Rocky Linux ${SELECTED_VERSION} - AppStream
mirrorlist=https://mirrors.rockylinux.org/mirrorlist?arch=x86_64&repo=AppStream-${SELECTED_VERSION}
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-rocky-${SELECTED_VERSION}
EOF
    else
        cat > "${MOUNT_ROOT}/etc/yum.repos.d/rocky.repo" << EOF
[baseos]
name=Rocky Linux ${SELECTED_VERSION} - BaseOS
mirrorlist=https://mirrors.rockylinux.org/mirrorlist?arch=x86_64&repo=BaseOS-${SELECTED_VERSION}
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-rocky-${SELECTED_VERSION}

[appstream]
name=Rocky Linux ${SELECTED_VERSION} - AppStream
mirrorlist=https://mirrors.rockylinux.org/mirrorlist?arch=x86_64&repo=AppStream-${SELECTED_VERSION}
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-rocky-${SELECTED_VERSION}

[extras]
name=Rocky Linux ${SELECTED_VERSION} - Extras
mirrorlist=https://mirrors.rockylinux.org/mirrorlist?arch=x86_64&repo=extras-${SELECTED_VERSION}
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-rocky-${SELECTED_VERSION}
EOF
    fi
    
    echo "${HOSTNAME}" > "${MOUNT_ROOT}/etc/hostname"
    
    cat > "${MOUNT_ROOT}/etc/hosts" << EOF
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
127.0.1.1   ${HOSTNAME}
EOF
    
    setup_chroot "$MOUNT_ROOT"
    
    print_step "Creating user..."
    run_chroot "$MOUNT_ROOT" "useradd -m -s /bin/bash -G wheel ${USERNAME}"
    echo "${USERNAME}:${PASSWORD}" | run_chroot "$MOUNT_ROOT" "chpasswd"
    
    print_step "Configuring sudo..."
    echo "%wheel ALL=(ALL) ALL" > "${MOUNT_ROOT}/etc/sudoers.d/wheel"
    chmod 440 "${MOUNT_ROOT}/etc/sudoers.d/wheel"
    
    configure_network_nm "$MOUNT_ROOT" "$PRIMARY_INTERFACE"
    configure_ssh "$MOUNT_ROOT" "$SSH_PORT" "$SSH_KEY" "$USERNAME"
    configure_fstab "$MOUNT_ROOT" "$INSTALL_DISK" "$BOOT_MODE"
    
    print_step "Installing bootloader..."
    if [[ "$BOOT_MODE" == "UEFI" ]]; then
        run_chroot "$MOUNT_ROOT" "grub2-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Rocky --recheck"
    else
        run_chroot "$MOUNT_ROOT" "grub2-install ${INSTALL_DISK}"
    fi
    run_chroot "$MOUNT_ROOT" "grub2-mkconfig -o /boot/grub2/grub.cfg"
    
    print_step "Enabling services..."
    run_chroot "$MOUNT_ROOT" "systemctl enable sshd"
    run_chroot "$MOUNT_ROOT" "systemctl enable NetworkManager"
    run_chroot "$MOUNT_ROOT" "systemctl enable firewalld"
    run_chroot "$MOUNT_ROOT" "systemctl enable chronyd"
    
    cleanup_chroot "$MOUNT_ROOT"
    unmount_partitions
    
    print_success "Rocky Linux ${SELECTED_VERSION} installation complete!"
    print_info "System will reboot into your new Rocky Linux installation."
}
