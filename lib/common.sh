#!/bin/bash

setup_chroot() {
    local target="$1"
    
    print_step "Setting up chroot environment..."
    
    mount --bind /dev "${target}/dev"
    mount --bind /dev/pts "${target}/dev/pts"
    mount --bind /proc "${target}/proc"
    mount --bind /sys "${target}/sys"
    
    cp /etc/resolv.conf "${target}/etc/resolv.conf"
    
    print_success "Chroot environment ready"
}

run_chroot() {
    local target="$1"
    shift
    chroot "$target" /bin/bash -c "$*"
}

cleanup_chroot() {
    local target="$1"
    
    print_step "Cleaning up chroot..."
    
    umount "${target}/sys" 2>/dev/null || true
    umount "${target}/proc" 2>/dev/null || true
    umount "${target}/dev/pts" 2>/dev/null || true
    umount "${target}/dev" 2>/dev/null || true
    
    print_success "Chroot cleaned up"
}

configure_ssh() {
    local target="$1"
    local port="$2"
    local ssh_key="$3"
    local username="$4"
    
    print_step "Configuring SSH access..."
    
    mkdir -p "${target}/etc/ssh"
    mkdir -p "${target}/home/${username}/.ssh"
    
    sed -i "s/^#*Port .*/Port ${port}/" "${target}/etc/ssh/sshd_config"
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' "${target}/etc/ssh/sshd_config"
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' "${target}/etc/ssh/sshd_config"
    sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' "${target}/etc/ssh/sshd_config"
    
    if [[ -n "$ssh_key" ]]; then
        echo "$ssh_key" > "${target}/home/${username}/.ssh/authorized_keys"
        chmod 700 "${target}/home/${username}/.ssh"
        chmod 600 "${target}/home/${username}/.ssh/authorized_keys"
        chroot "$target" chown -R "${username}:${username}" "/home/${username}/.ssh"
        print_success "SSH key added for ${username}"
    fi
    
    print_success "SSH configured on port ${port}"
}

create_user() {
    local target="$1"
    local username="$2"
    local password="$3"
    
    print_step "Creating user: ${username}"
    
    chroot "$target" useradd -m -s /bin/bash -G sudo,adm,cdrom,dip,plugdev "$username" 2>/dev/null || \
    chroot "$target" useradd -m -s /bin/bash -G wheel,adm,cdrom,dip,plugdev "$username" 2>/dev/null || \
    chroot "$target" useradd -m -s /bin/bash "$username"
    
    echo "${username}:${password}" | chroot "$target" chpasswd
    
    print_success "User ${username} created"
}

set_hostname() {
    local target="$1"
    local hostname="$2"
    
    print_step "Setting hostname: ${hostname}"
    
    echo "$hostname" > "${target}/etc/hostname"
    
    cat > "${target}/etc/hosts" << EOF
127.0.0.1   localhost
127.0.1.1   ${hostname}
::1         localhost ip6-localhost ip6-loopback
EOF
    
    print_success "Hostname set to ${hostname}"
}

configure_fstab() {
    local target="$1"
    local disk="$2"
    local boot_mode="$3"
    
    print_step "Configuring /etc/fstab..."
    
    local root_uuid=$(blkid -s UUID -o value "${disk}1" 2>/dev/null || blkid -s UUID -o value "${disk}2" 2>/dev/null)
    local boot_uuid=""
    
    [[ "$boot_mode" == "UEFI" ]] && boot_uuid=$(blkid -s UUID -o value "${disk}1" 2>/dev/null)
    
    cat > "${target}/etc/fstab" << EOF
UUID=${root_uuid}  /        ext4   defaults,noatime  0 1
EOF
    
    if [[ "$boot_mode" == "UEFI" && -n "$boot_uuid" ]]; then
        echo "UUID=${boot_uuid}  /boot/efi  vfat  defaults  0 2" >> "${target}/etc/fstab"
    fi
    
    echo "tmpfs  /tmp  tmpfs  defaults,noatime  0 0" >> "${target}/etc/fstab"
    
    print_success "/etc/fstab configured"
}

install_grub() {
    local target="$1"
    local disk="$2"
    local boot_mode="$3"
    
    print_step "Installing GRUB bootloader..."
    
    if [[ "$boot_mode" == "UEFI" ]]; then
        run_chroot "$target" "apt-get install -y grub-efi-amd64" 2>/dev/null || \
        run_chroot "$target" "dnf install -y grub2-efi-x64 shim-x64" 2>/dev/null || \
        run_chroot "$target" "pacman -S --noconfirm grub efibootmgr" 2>/dev/null
        
        run_chroot "$target" "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck"
    else
        run_chroot "$target" "apt-get install -y grub-pc" 2>/dev/null || \
        run_chroot "$target" "dnf install -y grub2-pc" 2>/dev/null || \
        run_chroot "$target" "pacman -S --noconfirm grub" 2>/dev/null
        
        run_chroot "$target" "grub-install ${disk}"
    fi
    
    run_chroot "$target" "grub-mkconfig -o /boot/grub/grub.cfg" 2>/dev/null || \
    run_chroot "$target" "grub2-mkconfig -o /boot/grub2/grub.cfg" 2>/dev/null
    
    print_success "GRUB installed"
}

show_progress() {
    local current="$1"
    local total="$2"
    local message="$3"
    
    local percent=$((current * 100 / total))
    local filled=$((percent / 2))
    local empty=$((50 - filled))
    
    printf "\r${CYAN}["
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "] ${percent}%% - ${message}${NC}"
    
    [[ $current -eq $total ]] && echo ""
}

download_with_progress() {
    local url="$1"
    local output="$2"
    local description="$3"
    
    print_info "Downloading: ${description}"
    
    if command -v wget &> /dev/null; then
        wget -q --show-progress -O "$output" "$url"
    elif command -v curl &> /dev/null; then
        curl -# -L -o "$output" "$url"
    else
        die "No download tool available"
    fi
}
