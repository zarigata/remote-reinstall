#!/bin/bash
#
# ██████╗ ███████╗██████╗  ██████╗ ███████╗██╗     ███████╗███████╗ ██████╗
# ██╔══██╗██╔════╝██╔══██╗██╔════╝ ██╔════╝██║     ██╔════╝██╔════╝██╔════╝
# ██████╔╝█████╗  ██████╔╝██║  ███╗█████╗  ██║     █████╗  ███████╗██║     
# ██╔══██╗██╔══╝  ██╔══██╗██║   ██║██╔══╝  ██║     ██╔══╝  ╚════██║██║     
# ██║  ██║███████╗██║  ██║╚██████╔╝███████╗███████╗███████╗███████║╚██████╗
# ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚══════╝╚══════╝╚══════╝ ╚═════╝
#
# RAM-Based Second-Stage Installer
# This script runs from a RAM-based Alpine Linux system
# and performs the actual disk installation
#
# by Zarigata | FeverDream
#

set -o pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

CONFIG_FILE=""
LOG_FILE="/tmp/ram-installer.log"

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    echo -e "${CYAN}[$timestamp]${NC} $message"
}

print_error() {
    echo -e "${RED}✗ ERROR: $*${NC}" >&2
    log "ERROR" "$*"
}

print_success() {
    echo -e "${GREEN}✓ $*${NC}"
    log "INFO" "$*"
}

print_warning() {
    echo -e "${YELLOW}⚠ WARNING: $*${NC}"
    log "WARNING" "$*"
}

print_info() {
    echo -e "${BLUE}ℹ $*${NC}"
    log "INFO" "$*"
}

print_step() {
    echo ""
    echo -e "${MAGENTA}▶ $*${NC}"
    log "STEP" "$*"
}

die() {
    print_error "$*"
    echo ""
    echo -e "${YELLOW}Installation failed. Log saved at: ${LOG_FILE}${NC}"
    echo -e "${YELLOW}Dropping to shell for debugging...${NC}"
    exec /bin/sh
}

find_config_file() {
    local candidate
    for candidate in /installer/config.sh /tmp/reinstall-config.sh /mnt/ram-boot/installer/config.sh; do
        if [[ -f "$candidate" ]]; then
            CONFIG_FILE="$candidate"
            return 0
        fi
    done
    return 1
}

load_config() {
    find_config_file || die "Configuration file not found in embedded installer paths"
    source "$CONFIG_FILE"

    local required_vars=("SELECTED_DISTRO" "SELECTED_VERSION" "INSTALL_DISK" \
                         "HOSTNAME" "USERNAME" "PASSWORD" "SSH_PORT" \
                         "BOOT_MODE" "ARCH" "PRIMARY_INTERFACE" "PRIMARY_IP")
    local var
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            die "Missing required configuration: $var"
        fi
    done

    print_success "Configuration loaded from ${CONFIG_FILE}"
    print_info "Distribution: ${SELECTED_DISTRO} ${SELECTED_VERSION}"
    print_info "Target disk: ${INSTALL_DISK}"
    print_info "Hostname: ${HOSTNAME}"
    print_info "Network: ${PRIMARY_IP} on ${PRIMARY_INTERFACE}"
}

wait_for_network() {
    local attempts=30
    local attempt=1

    print_step "Waiting for live network access..."
    while (( attempt <= attempts )); do
        if ip -4 addr show "$PRIMARY_INTERFACE" 2>/dev/null | grep -q 'inet ' && ip route | grep -q '^default'; then
            print_success "Network appears ready"
            return 0
        fi
        print_info "Network not ready yet (${attempt}/${attempts})"
        sleep 2
        attempt=$((attempt + 1))
    done

    die "Timed out waiting for network on ${PRIMARY_INTERFACE}"
}

install_runtime_dependencies() {
    print_step "Installing live-environment dependencies..."

    apk update || die "Failed to refresh Alpine package indexes"

    local packages=(bash coreutils curl wget util-linux parted e2fsprogs dosfstools gdisk openssh tar)
    case "$SELECTED_DISTRO" in
        ubuntu|debian)
            packages+=(debootstrap)
            ;;
        proxmox)
            packages+=(debootstrap gnupg)
            ;;
    esac

    apk add --no-cache "${packages[@]}" || die "Failed to install live-environment dependencies"
    print_success "Live-environment dependencies installed"
}

wipe_disk() {
    local disk="$1"
    local part

    print_step "Wiping disk: ${disk}"
    print_warning "ALL DATA WILL BE ERASED!"

    for part in $(lsblk -ln -o NAME "$disk" 2>/dev/null | tail -n +2); do
        umount -f "/dev/$part" 2>/dev/null || true
    done

    wipefs -a "$disk" 2>/dev/null || true
    sgdisk -Z "$disk" 2>/dev/null || true
    sleep 2

    print_success "Disk wiped: ${disk}"
}

partition_disk_bios() {
    local disk="$1"
    local root_part

    print_step "Partitioning disk (BIOS/MBR): ${disk}"
    parted -s "$disk" mklabel msdos
    parted -s "$disk" mkpart primary ext4 1MiB 100%
    parted -s "$disk" set 1 boot on
    sleep 2

    root_part="${disk}1"
    mkfs.ext4 -F -L "ROOT" "$root_part"

    ROOT_PARTITION="$root_part"
    BOOT_PARTITION=""

    print_success "Partitioning complete"
    print_info "Root: ${root_part}"
}

partition_disk_uefi() {
    local disk="$1"
    local efi_part
    local root_part

    print_step "Partitioning disk (UEFI/GPT): ${disk}"
    parted -s "$disk" mklabel gpt
    parted -s "$disk" mkpart ESP fat32 1MiB 513MiB
    parted -s "$disk" set 1 esp on
    parted -s "$disk" mkpart primary ext4 513MiB 100%
    sleep 2

    efi_part="${disk}1"
    root_part="${disk}2"

    mkfs.vfat -F 32 -n "EFI" "$efi_part"
    mkfs.ext4 -F -L "ROOT" "$root_part"

    ROOT_PARTITION="$root_part"
    BOOT_PARTITION="$efi_part"

    print_success "Partitioning complete"
    print_info "EFI: ${efi_part}"
    print_info "Root: ${root_part}"
}

partition_disk() {
    local disk="$1"

    wipe_disk "$disk"

    if [[ "$BOOT_MODE" == "UEFI" ]]; then
        partition_disk_uefi "$disk"
    else
        partition_disk_bios "$disk"
    fi
}

MOUNT_ROOT="/mnt/target"

mount_partitions() {
    print_step "Mounting partitions..."
    mkdir -p "$MOUNT_ROOT"
    mount "$ROOT_PARTITION" "$MOUNT_ROOT"

    if [[ "$BOOT_MODE" == "UEFI" && -n "$BOOT_PARTITION" ]]; then
        mkdir -p "${MOUNT_ROOT}/boot/efi"
        mount "$BOOT_PARTITION" "${MOUNT_ROOT}/boot/efi"
    fi

    print_success "Partitions mounted at ${MOUNT_ROOT}"
}

unmount_partitions() {
    print_step "Unmounting partitions..."
    sync

    if [[ "$BOOT_MODE" == "UEFI" && -n "$BOOT_PARTITION" ]]; then
        umount "${MOUNT_ROOT}/boot/efi" 2>/dev/null || true
    fi
    umount "$MOUNT_ROOT" 2>/dev/null || true

    print_success "Partitions unmounted"
}

save_network_config() {
    local target="$1"
    local ip_addr netmask gateway dns

    print_step "Saving network configuration..."

    ip_addr=$(ip -4 addr show "$PRIMARY_INTERFACE" | grep inet | awk '{print $2}' | cut -d/ -f1)
    netmask=$(ip -4 addr show "$PRIMARY_INTERFACE" | grep inet | awk '{print $2}' | cut -d/ -f2)
    gateway=$(ip route | grep default | awk '{print $3}')
    dns=$(grep '^nameserver' /etc/resolv.conf | head -1 | awk '{print $2}')

    case "$SELECTED_DISTRO" in
        ubuntu|debian|proxmox)
            cat > "${target}/etc/network/interfaces" << EOF_INTERFACES
auto lo
iface lo inet loopback

auto ${PRIMARY_INTERFACE}
iface ${PRIMARY_INTERFACE} inet static
    address ${ip_addr}/${netmask}
    gateway ${gateway}
    dns-nameservers ${dns}
EOF_INTERFACES
            ;;
        alpine)
            cat > "${target}/etc/network/interfaces" << EOF_ALPINE
auto lo
iface lo inet loopback

auto ${PRIMARY_INTERFACE}
iface ${PRIMARY_INTERFACE} inet static
    address ${ip_addr}
    netmask ${netmask}
    gateway ${gateway}
EOF_ALPINE
            echo "nameserver ${dns}" > "${target}/etc/resolv.conf"
            ;;
        *)
            die "Unsupported distro for network config in RAM installer: ${SELECTED_DISTRO}"
            ;;
    esac

    print_success "Network configuration saved"
    print_info "IP: ${ip_addr}/${netmask}"
    print_info "Gateway: ${gateway}"
    print_info "DNS: ${dns}"
}

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
    chroot "$target" /bin/sh -c "$*"
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

create_user() {
    local target="$1"
    local username="$2"
    local password="$3"

    print_step "Creating user: ${username}"
    run_chroot "$target" "useradd -m -s /bin/bash -G sudo,adm,cdrom,dip,plugdev '${username}' 2>/dev/null || useradd -m -s /bin/bash -G wheel,adm,cdrom,dip,plugdev '${username}' 2>/dev/null || useradd -m -s /bin/bash '${username}'"
    echo "${username}:${password}" | chroot "$target" chpasswd

    print_success "User ${username} created"
}

set_hostname() {
    local target="$1"
    local hostname="$2"

    print_step "Setting hostname: ${hostname}"
    echo "$hostname" > "${target}/etc/hostname"
    cat > "${target}/etc/hosts" << EOF_HOSTS
127.0.0.1   localhost
127.0.1.1   ${hostname}
::1         localhost ip6-localhost ip6-loopback
EOF_HOSTS

    print_success "Hostname set to ${hostname}"
}

configure_ssh() {
    local target="$1"
    local port="$2"
    local ssh_key="$3"
    local username="$4"

    print_step "Configuring SSH access..."
    mkdir -p "${target}/etc/ssh" "${target}/home/${username}/.ssh"

    if [[ -d "${target}/etc/ssh/sshd_config.d" ]]; then
        cat > "${target}/etc/ssh/sshd_config.d/remote-reinstall.conf" << EOF_SSHD
Port ${port}
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
EOF_SSHD
    else
        sed -i "s/^#*Port .*/Port ${port}/" "${target}/etc/ssh/sshd_config"
        sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' "${target}/etc/ssh/sshd_config"
        sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' "${target}/etc/ssh/sshd_config"
        sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' "${target}/etc/ssh/sshd_config"
    fi

    if [[ -n "$ssh_key" ]]; then
        echo "$ssh_key" > "${target}/home/${username}/.ssh/authorized_keys"
        chmod 700 "${target}/home/${username}/.ssh"
        chmod 600 "${target}/home/${username}/.ssh/authorized_keys"
        chroot "$target" chown -R "${username}:${username}" "/home/${username}/.ssh"
        print_success "SSH key added for ${username}"
    fi

    print_success "SSH configured on port ${port}"
}

configure_fstab() {
    local target="$1"
    local root_uuid boot_uuid

    print_step "Configuring /etc/fstab..."
    root_uuid=$(blkid -s UUID -o value "$ROOT_PARTITION")
    boot_uuid=""
    [[ -n "$BOOT_PARTITION" ]] && boot_uuid=$(blkid -s UUID -o value "$BOOT_PARTITION")

    cat > "${target}/etc/fstab" << EOF_FSTAB
UUID=${root_uuid}  /        ext4   defaults,noatime  0 1
EOF_FSTAB
    if [[ -n "$boot_uuid" ]]; then
        echo "UUID=${boot_uuid}  /boot/efi  vfat  defaults  0 2" >> "${target}/etc/fstab"
    fi
    echo "tmpfs  /tmp  tmpfs  defaults,noatime  0 0" >> "${target}/etc/fstab"

    print_success "/etc/fstab configured"
}

install_grub() {
    local target="$1"
    local disk="$2"

    print_step "Installing GRUB bootloader..."
    if [[ "$BOOT_MODE" == "UEFI" ]]; then
        run_chroot "$target" "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck --no-nvram"
        mkdir -p "${target}/boot/efi/EFI/BOOT"
        cp "${target}/boot/efi/EFI/GRUB/grubx64.efi" "${target}/boot/efi/EFI/BOOT/BOOTX64.EFI" 2>/dev/null || true
    else
        run_chroot "$target" "grub-install ${disk}"
    fi

    run_chroot "$target" "grub-mkconfig -o /boot/grub/grub.cfg" 2>/dev/null || \
    run_chroot "$target" "grub2-mkconfig -o /boot/grub2/grub.cfg" 2>/dev/null

    print_success "GRUB installed"
}

install_debian() {
    local codename
    case "$SELECTED_VERSION" in
        12) codename="bookworm" ;;
        11) codename="bullseye" ;;
        *) die "Unsupported Debian version: ${SELECTED_VERSION}" ;;
    esac

    print_step "Installing Debian ${SELECTED_VERSION} (${codename})..."
    print_info "This may take 10-20 minutes..."
    debootstrap --arch=amd64 --variant=minbase "$codename" "$MOUNT_ROOT" http://deb.debian.org/debian/
    print_success "Base system installed"

    cat > "${MOUNT_ROOT}/etc/apt/sources.list" << EOF_APT
deb http://deb.debian.org/debian ${codename} main contrib non-free-firmware
deb http://deb.debian.org/debian ${codename}-updates main contrib non-free-firmware
deb http://security.debian.org/debian-security ${codename}-security main contrib non-free-firmware
EOF_APT

    setup_chroot "$MOUNT_ROOT"
    run_chroot "$MOUNT_ROOT" "apt-get update"
    run_chroot "$MOUNT_ROOT" "DEBIAN_FRONTEND=noninteractive apt-get install -y linux-image-amd64 grub-efi-amd64 grub-pc openssh-server sudo systemd systemd-sysv locales tzdata ifupdown isc-dhcp-client iproute2 --no-install-recommends"
    run_chroot "$MOUNT_ROOT" "sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen"
    run_chroot "$MOUNT_ROOT" "locale-gen en_US.UTF-8"
    echo "LANG=en_US.UTF-8" > "${MOUNT_ROOT}/etc/default/locale"
    run_chroot "$MOUNT_ROOT" "ln -sf /usr/share/zoneinfo/UTC /etc/localtime"

    set_hostname "$MOUNT_ROOT" "$HOSTNAME"
    create_user "$MOUNT_ROOT" "$USERNAME" "$PASSWORD"
    save_network_config "$MOUNT_ROOT"
    configure_ssh "$MOUNT_ROOT" "$SSH_PORT" "$SSH_KEY" "$USERNAME"
    configure_fstab "$MOUNT_ROOT"
    install_grub "$MOUNT_ROOT" "$INSTALL_DISK"
    run_chroot "$MOUNT_ROOT" "systemctl enable ssh"
    cleanup_chroot "$MOUNT_ROOT"

    print_success "Debian ${SELECTED_VERSION} installation complete!"
}

install_ubuntu() {
    local codename
    case "$SELECTED_VERSION" in
        24.04) codename="noble" ;;
        22.04) codename="jammy" ;;
        20.04) codename="focal" ;;
        *) die "Unsupported Ubuntu version: ${SELECTED_VERSION}" ;;
    esac

    print_step "Installing Ubuntu ${SELECTED_VERSION} (${codename})..."
    debootstrap --arch=amd64 --variant=minbase "$codename" "$MOUNT_ROOT" http://archive.ubuntu.com/ubuntu/
    print_success "Base system installed"

    cat > "${MOUNT_ROOT}/etc/apt/sources.list" << EOF_UBUNTU_APT
deb http://archive.ubuntu.com/ubuntu ${codename} main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu ${codename}-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu ${codename}-security main restricted universe multiverse
EOF_UBUNTU_APT

    setup_chroot "$MOUNT_ROOT"
    run_chroot "$MOUNT_ROOT" "apt-get update"
    run_chroot "$MOUNT_ROOT" "DEBIAN_FRONTEND=noninteractive apt-get install -y linux-image-generic grub-efi-amd64 grub-pc openssh-server sudo systemd systemd-sysv locales tzdata netplan.io --no-install-recommends"
    run_chroot "$MOUNT_ROOT" "sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen"
    run_chroot "$MOUNT_ROOT" "locale-gen en_US.UTF-8"
    echo "LANG=en_US.UTF-8" > "${MOUNT_ROOT}/etc/default/locale"
    run_chroot "$MOUNT_ROOT" "ln -sf /usr/share/zoneinfo/UTC /etc/localtime"

    set_hostname "$MOUNT_ROOT" "$HOSTNAME"
    create_user "$MOUNT_ROOT" "$USERNAME" "$PASSWORD"

    local ip_addr netmask gateway
    ip_addr=$(ip -4 addr show "$PRIMARY_INTERFACE" | grep inet | awk '{print $2}' | cut -d/ -f1)
    netmask=$(ip -4 addr show "$PRIMARY_INTERFACE" | grep inet | awk '{print $2}' | cut -d/ -f2)
    gateway=$(ip route | grep default | awk '{print $3}')
    mkdir -p "${MOUNT_ROOT}/etc/netplan"
    cat > "${MOUNT_ROOT}/etc/netplan/01-netcfg.yaml" << EOF_NETPLAN
network:
  version: 2
  ethernets:
    ${PRIMARY_INTERFACE}:
      addresses:
        - ${ip_addr}/${netmask}
      gateway4: ${gateway}
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
EOF_NETPLAN

    configure_ssh "$MOUNT_ROOT" "$SSH_PORT" "$SSH_KEY" "$USERNAME"
    configure_fstab "$MOUNT_ROOT"
    install_grub "$MOUNT_ROOT" "$INSTALL_DISK"
    run_chroot "$MOUNT_ROOT" "systemctl enable ssh"
    cleanup_chroot "$MOUNT_ROOT"

    print_success "Ubuntu ${SELECTED_VERSION} installation complete!"
}

install_proxmox() {
    local debian_codename
    local pve_repo

    case "$SELECTED_VERSION" in
        8)
            debian_codename="bookworm"
            pve_repo="bookworm"
            ;;
        7)
            debian_codename="bullseye"
            pve_repo="bullseye"
            ;;
        *)
            die "Unsupported Proxmox version: ${SELECTED_VERSION}"
            ;;
    esac

    print_step "Installing Proxmox VE ${SELECTED_VERSION}..."
    print_info "Bootstrapping Debian ${debian_codename} base system"
    debootstrap --arch=amd64 --variant=minbase "$debian_codename" "$MOUNT_ROOT" http://deb.debian.org/debian/
    print_success "Base system installed"

    cat > "${MOUNT_ROOT}/etc/apt/sources.list" << EOF_PROXMOX_APT
deb http://deb.debian.org/debian ${debian_codename} main contrib non-free-firmware
deb http://deb.debian.org/debian ${debian_codename}-updates main contrib non-free-firmware
deb http://security.debian.org/debian-security ${debian_codename}-security main contrib non-free-firmware

deb [arch=amd64] http://download.proxmox.com/debian/pve ${pve_repo} pve-no-subscription
EOF_PROXMOX_APT

    setup_chroot "$MOUNT_ROOT"
    run_chroot "$MOUNT_ROOT" "apt-get update"
    run_chroot "$MOUNT_ROOT" "DEBIAN_FRONTEND=noninteractive apt-get install -y linux-image-amd64 grub-efi-amd64 grub-pc openssh-server sudo locales tzdata curl wget gnupg --no-install-recommends"
    run_chroot "$MOUNT_ROOT" "curl -fsSL https://enterprise.proxmox.com/debian/proxmox-release-${pve_repo}.gpg -o /etc/apt/trusted.gpg.d/proxmox-release-${pve_repo}.gpg"
    run_chroot "$MOUNT_ROOT" "apt-get update"
    run_chroot "$MOUNT_ROOT" "DEBIAN_FRONTEND=noninteractive apt-get install -y proxmox-ve postfix open-iscsi --no-install-recommends" || \
        print_warning "Some Proxmox packages failed to install; review the log from the rescue shell if the rebooted system is incomplete"
    run_chroot "$MOUNT_ROOT" "sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen"
    run_chroot "$MOUNT_ROOT" "locale-gen en_US.UTF-8"
    echo "LANG=en_US.UTF-8" > "${MOUNT_ROOT}/etc/default/locale"
    run_chroot "$MOUNT_ROOT" "ln -sf /usr/share/zoneinfo/UTC /etc/localtime"

    set_hostname "$MOUNT_ROOT" "$HOSTNAME"
    create_user "$MOUNT_ROOT" "$USERNAME" "$PASSWORD"
    save_network_config "$MOUNT_ROOT"
    configure_ssh "$MOUNT_ROOT" "$SSH_PORT" "$SSH_KEY" "$USERNAME"
    configure_fstab "$MOUNT_ROOT"
    install_grub "$MOUNT_ROOT" "$INSTALL_DISK"
    run_chroot "$MOUNT_ROOT" "systemctl enable ssh"
    run_chroot "$MOUNT_ROOT" "systemctl enable pveproxy" 2>/dev/null || true
    run_chroot "$MOUNT_ROOT" "systemctl enable pvedaemon" 2>/dev/null || true
    run_chroot "$MOUNT_ROOT" "systemctl enable pvestatd" 2>/dev/null || true
    cleanup_chroot "$MOUNT_ROOT"

    print_success "Proxmox VE ${SELECTED_VERSION} installation complete!"
}

install_alpine() {
    local rootfs_url repo_main repo_community

    print_step "Installing Alpine ${SELECTED_VERSION}..."

    case "$SELECTED_VERSION" in
        3.19|3.18)
            rootfs_url="https://dl-cdn.alpinelinux.org/alpine/v${SELECTED_VERSION}/releases/x86_64/alpine-minirootfs-${SELECTED_VERSION}.0-x86_64.tar.gz"
            repo_main="https://dl-cdn.alpinelinux.org/alpine/v${SELECTED_VERSION}/main"
            repo_community="https://dl-cdn.alpinelinux.org/alpine/v${SELECTED_VERSION}/community"
            ;;
        edge)
            die "Alpine edge is not yet supported from the RAM installer path"
            ;;
        *)
            die "Unsupported Alpine version: ${SELECTED_VERSION}"
            ;;
    esac

    print_info "Downloading Alpine rootfs..."
    wget -q -O /tmp/alpine-rootfs.tar.gz "$rootfs_url" || curl -sL -o /tmp/alpine-rootfs.tar.gz "$rootfs_url" || die "Failed to download Alpine rootfs"
    tar -xzf /tmp/alpine-rootfs.tar.gz -C "$MOUNT_ROOT"
    print_success "Base system installed"

    cat > "${MOUNT_ROOT}/etc/apk/repositories" << EOF_APK_REPOS
${repo_main}
${repo_community}
EOF_APK_REPOS

    setup_chroot "$MOUNT_ROOT"
    run_chroot "$MOUNT_ROOT" "apk update"
    run_chroot "$MOUNT_ROOT" "apk add linux-lts grub-efi grub-bios openssh sudo openrc e2fsprogs util-linux"

    set_hostname "$MOUNT_ROOT" "$HOSTNAME"
    create_user "$MOUNT_ROOT" "$USERNAME" "$PASSWORD"
    save_network_config "$MOUNT_ROOT"
    configure_ssh "$MOUNT_ROOT" "$SSH_PORT" "$SSH_KEY" "$USERNAME"
    configure_fstab "$MOUNT_ROOT"
    install_grub "$MOUNT_ROOT" "$INSTALL_DISK"
    run_chroot "$MOUNT_ROOT" "rc-update add sshd default"
    run_chroot "$MOUNT_ROOT" "rc-update add networking boot"
    cleanup_chroot "$MOUNT_ROOT"

    print_success "Alpine ${SELECTED_VERSION} installation complete!"
}

show_banner() {
    echo -e "${CYAN}"
    cat << 'EOF_BANNER'
 ██████╗ ███████╗██████╗  ██████╗ ███████╗██╗     ███████╗███████╗ ██████╗
 ██╔══██╗██╔════╝██╔══██╗██╔════╝ ██╔════╝██║     ██╔════╝██╔════╝██╔════╝
 ██████╔╝█████╗  ██████╔╝██║  ███╗█████╗  ██║     █████╗  ███████╗██║     
 ██╔══██╗██╔══╝  ██╔══██╗██║   ██║██╔══╝  ██║     ██╔══╝  ╚════██║██║     
 ██║  ██║███████╗██║  ██║╚██████╔╝███████╗███████╗███████╗███████║╚██████╗
 ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚══════╝╚══════╝╚══════╝ ╚═════╝
EOF_BANNER
    echo -e "${NC}"
    echo -e "${WHITE}  RAM-Based Second-Stage Installer${NC}"
    echo -e "${MAGENTA}  by Zarigata${NC} ${WHITE}|${NC} ${CYAN}FeverDream${NC}"
    echo ""
}

show_completion() {
    print_success "Installation completed successfully!"
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${WHITE}Your new ${SELECTED_DISTRO^} system is ready!${NC}"
    echo ""
    echo -e "  ${CYAN}Connection Details:${NC}"
    echo -e "  ${GREEN}➤${NC} IP Address:  ${PRIMARY_IP}"
    echo -e "  ${GREEN}➤${NC} SSH Port:    ${SSH_PORT}"
    echo -e "  ${GREEN}➤${NC} Username:    ${USERNAME}"
    echo ""
    echo -e "  ${YELLOW}Connect with:${NC}"
    echo -e "  ${WHITE}ssh -p ${SSH_PORT} ${USERNAME}@${PRIMARY_IP}${NC}"
    echo ""
    echo -e "  ${YELLOW}The system will reboot in 5 seconds...${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

main() {
    show_banner
    print_info "Starting RAM-based installation..."
    print_info "Log file: ${LOG_FILE}"
    echo "=== RAM Installer Started at $(date) ===" > "$LOG_FILE"

    load_config
    wait_for_network
    install_runtime_dependencies
    partition_disk "$INSTALL_DISK"
    mount_partitions

    case "$SELECTED_DISTRO" in
        debian)
            install_debian
            ;;
        ubuntu)
            install_ubuntu
            ;;
        proxmox)
            install_proxmox
            ;;
        alpine)
            install_alpine
            ;;
        *)
            die "Unsupported distribution from RAM installer: ${SELECTED_DISTRO}"
            ;;
    esac

    unmount_partitions
    show_completion
    print_info "Rebooting in 5 seconds..."
    sleep 5
    print_info "Rebooting now..."
    reboot -f
}

main "$@"
