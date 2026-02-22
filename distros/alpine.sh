#!/bin/bash

install_alpine() {
    print_step "Installing Alpine Linux ${SELECTED_VERSION}..."
    
    source "${LIB_DIR}/partition.sh"
    source "${LIB_DIR}/network.sh"
    source "${LIB_DIR}/common.sh"
    
    local repo_url
    case "$SELECTED_VERSION" in
        3.19) repo_url="https://dl-cdn.alpinelinux.org/alpine/v3.19" ;;
        3.18) repo_url="https://dl-cdn.alpinelinux.org/alpine/v3.18" ;;
        edge) repo_url="https://dl-cdn.alpinelinux.org/alpine/edge" ;;
        *) die "Unsupported Alpine version: ${SELECTED_VERSION}" ;;
    esac
    
    print_info "Repository: ${repo_url}"
    
    print_step "Installing required packages..."
    apk add --no-cache parted e2fsprogs dosfstools util-linux sfdisk
    
    partition_disk "$INSTALL_DISK" "$BOOT_MODE"
    mount_partitions "$INSTALL_DISK" "$BOOT_MODE"
    save_network_config "$MOUNT_ROOT"
    
    print_step "Installing Alpine Linux base system using apk..."
    print_info "This may take 5-15 minutes depending on network speed..."
    
    mkdir -p "${MOUNT_ROOT}/etc/apk"
    echo "${repo_url}/main" > "${MOUNT_ROOT}/etc/apk/repositories"
    echo "${repo_url}/community" >> "${MOUNT_ROOT}/etc/apk/repositories"
    
    apk add --root="$MOUNT_ROOT" --initdb \
        alpine-base \
        linux-virt \
        linux-firmware-none \
        grub \
        grub-efi \
        openssh \
        sudo \
        openrc \
        busybox-openrc \
        networking \
        chrony \
        util-linux \
        shadow \
        bash \
        coreutils \
        nano \
        vim
    
    print_success "Base system installed"
    
    print_step "Configuring Alpine Linux..."
    
    echo "${HOSTNAME}" > "${MOUNT_ROOT}/etc/hostname"
    
    cat > "${MOUNT_ROOT}/etc/hosts" << EOF
127.0.0.1   localhost localhost.localdomain
::1         localhost localhost.localdomain
127.0.1.1   ${HOSTNAME}
EOF
    
    print_step "Configuring networking..."
    mkdir -p "${MOUNT_ROOT}/etc/network"
    cat > "${MOUNT_ROOT}/etc/network/interfaces" << EOF
auto lo
iface lo inet loopback

auto ${PRIMARY_INTERFACE}
iface ${PRIMARY_INTERFACE} inet static
    address ${PRIMARY_IP}
    netmask 255.255.255.0
    gateway $(ip route | grep default | awk '{print $3}')
EOF
    
    echo "nameserver 8.8.8.8" > "${MOUNT_ROOT}/etc/resolv.conf"
    echo "nameserver 8.8.4.4" >> "${MOUNT_ROOT}/etc/resolv.conf"
    
    print_step "Configuring APK repositories..."
    cat > "${MOUNT_ROOT}/etc/apk/repositories" << EOF
${repo_url}/main
${repo_url}/community
EOF
    
    print_step "Configuring SSH..."
    mkdir -p "${MOUNT_ROOT}/etc/ssh"
    cat > "${MOUNT_ROOT}/etc/ssh/sshd_config" << EOF
Port ${SSH_PORT}
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication yes
ChallengeResponseAuthentication no
UsePAM no
Subsystem sftp /usr/lib/ssh/sftp-server
EOF
    
    setup_chroot "$MOUNT_ROOT"
    
    print_step "Creating user..."
    run_chroot "$MOUNT_ROOT" "adduser -D -s /bin/bash ${USERNAME}"
    run_chroot "$MOUNT_ROOT" "adduser ${USERNAME} wheel"
    echo "${USERNAME}:${PASSWORD}" | run_chroot "$MOUNT_ROOT" "chpasswd"
    
    print_step "Configuring sudo..."
    echo "%wheel ALL=(ALL) ALL" > "${MOUNT_ROOT}/etc/sudoers.d/wheel"
    chmod 440 "${MOUNT_ROOT}/etc/sudoers.d/wheel"
    
    print_step "Setting root password..."
    echo "root:${PASSWORD}" | run_chroot "$MOUNT_ROOT" "chpasswd"
    
    if [[ -n "$SSH_KEY" ]]; then
        print_step "Adding SSH key..."
        mkdir -p "${MOUNT_ROOT}/home/${USERNAME}/.ssh"
        echo "$SSH_KEY" > "${MOUNT_ROOT}/home/${USERNAME}/.ssh/authorized_keys"
        chmod 700 "${MOUNT_ROOT}/home/${USERNAME}/.ssh"
        chmod 600 "${MOUNT_ROOT}/home/${USERNAME}/.ssh/authorized_keys"
        chroot "$MOUNT_ROOT" chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}/.ssh"
    fi
    
    configure_fstab "$MOUNT_ROOT" "$INSTALL_DISK" "$BOOT_MODE"
    
    print_step "Installing bootloader..."
    if [[ "$BOOT_MODE" == "UEFI" ]]; then
        apk add --root="$MOUNT_ROOT" grub-efi
        run_chroot "$MOUNT_ROOT" "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Alpine --recheck"
    else
        apk add --root="$MOUNT_ROOT" grub-bios
        run_chroot "$MOUNT_ROOT" "grub-install ${INSTALL_DISK}"
    fi
    run_chroot "$MOUNT_ROOT" "grub-mkconfig -o /boot/grub/grub.cfg"
    
    print_step "Configuring init system..."
    run_chroot "$MOUNT_ROOT" "rc-update add devfs sysinit"
    run_chroot "$MOUNT_ROOT" "rc-update add dmesg sysinit"
    run_chroot "$MOUNT_ROOT" "rc-update add mdev sysinit"
    
    run_chroot "$MOUNT_ROOT" "rc-update add hwclock boot"
    run_chroot "$MOUNT_ROOT" "rc-update add modules boot"
    run_chroot "$MOUNT_ROOT" "rc-update add sysctl boot"
    run_chroot "$MOUNT_ROOT" "rc-update add hostname boot"
    run_chroot "$MOUNT_ROOT" "rc-update add bootmisc boot"
    run_chroot "$MOUNT_ROOT" "rc-update add networking boot"
    
    run_chroot "$MOUNT_ROOT" "rc-update add sshd default"
    run_chroot "$MOUNT_ROOT" "rc-update add chronyd default"
    
    print_step "Configuring inittab..."
    cat > "${MOUNT_ROOT}/etc/inittab" << 'EOF'
::sysinit:/sbin/openrc sysinit
::sysinit:/sbin/openrc boot
::wait:/sbin/openrc default

tty1::respawn:/sbin/getty 38400 tty1
ttyS0::respawn:/sbin/getty -L ttyS0 115200 vt100

::ctrlaltdel:/sbin/reboot
::shutdown:/sbin/openrc shutdown
EOF
    
    cleanup_chroot "$MOUNT_ROOT"
    unmount_partitions
    
    print_success "Alpine Linux ${SELECTED_VERSION} installation complete!"
    print_info "System will reboot into your new Alpine Linux installation."
}
