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

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Configuration file location (passed from first stage)
CONFIG_FILE="/tmp/reinstall-config.sh"
LOG_FILE="/tmp/ram-installer.log"

#===================================================================================
# LOGGING
#===================================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
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

#===================================================================================
# CONFIGURATION LOADING
#===================================================================================

load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        die "Configuration file not found: $CONFIG_FILE"
    fi
    
    source "$CONFIG_FILE"
    
    # Validate required variables
    local required_vars=("SELECTED_DISTRO" "SELECTED_VERSION" "INSTALL_DISK" 
                         "HOSTNAME" "USERNAME" "PASSWORD" "SSH_PORT"
                         "BOOT_MODE" "ARCH" "PRIMARY_INTERFACE" "PRIMARY_IP")
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            die "Missing required configuration: $var"
        fi
    done
    
    print_success "Configuration loaded"
    print_info "Distribution: ${SELECTED_DISTRO} ${SELECTED_VERSION}"
    print_info "Target disk: ${INSTALL_DISK}"
    print_info "Hostname: ${HOSTNAME}"
    print_info "Network: ${PRIMARY_IP} on ${PRIMARY_INTERFACE}"
}

#===================================================================================
# DISK OPERATIONS (Safe from RAM)
#===================================================================================

wipe_disk() {
    local disk="$1"
    
    print_step "Wiping disk: ${disk}"
    print_warning "ALL DATA WILL BE ERASED!"
    
    # Unmount any existing partitions
    for part in $(lsblk -ln -o NAME "$disk" 2>/dev/null | tail -n +2); do
        umount -f "/dev/$part" 2>/dev/null || true
    done
    
    # Wipe partition table and filesystem signatures
    wipefs -a "$disk" 2>/dev/null || true
    sgdisk -Z "$disk" 2>/dev/null || true
    
    # Small delay to let kernel sync
    sleep 2
    
    print_success "Disk wiped: ${disk}"
}

partition_disk_bios() {
    local disk="$1"
    
    print_step "Partitioning disk (BIOS/MBR): ${disk}"
    
    # Create MBR partition table
    parted -s "$disk" mklabel msdos
    
    # Create root partition (use entire disk, leave 1MB at end)
    parted -s "$disk" mkpart primary ext4 1MiB 100%
    parted -s "$disk" set 1 boot on
    
    # Small delay
    sleep 2
    
    # Format root partition
    local root_part="${disk}1"
    mkfs.ext4 -F -L "ROOT" "$root_part"
    
    ROOT_PARTITION="$root_part"
    BOOT_PARTITION=""
    
    print_success "Partitioning complete"
    print_info "Root: ${root_part}"
}

partition_disk_uefi() {
    local disk="$1"
    
    print_step "Partitioning disk (UEFI/GPT): ${disk}"
    
    # Create GPT partition table
    parted -s "$disk" mklabel gpt
    
    # Create EFI partition (512MB)
    parted -s "$disk" mkpart ESP fat32 1MiB 513MiB
    parted -s "$disk" set 1 esp on
    
    # Create root partition (rest of disk)
    parted -s "$disk" mkpart primary ext4 513MiB 100%
    
    # Small delay
    sleep 2
    
    # Format partitions
    local efi_part="${disk}1"
    local root_part="${disk}2"
    
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

#===================================================================================
# MOUNT OPERATIONS
#===================================================================================

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

#===================================================================================
# NETWORK CONFIGURATION
#===================================================================================

save_network_config() {
    local target="$1"
    
    print_step "Saving network configuration..."
    
    # Get current network info from RAM system
    local ip_addr netmask gateway dns
    
    ip_addr=$(ip -4 addr show "$PRIMARY_INTERFACE" | grep inet | awk '{print $2}' | cut -d/ -f1)
    netmask=$(ip -4 addr show "$PRIMARY_INTERFACE" | grep inet | awk '{print $2}' | cut -d/ -f2)
    gateway=$(ip route | grep default | awk '{print $3}')
    dns=$(cat /etc/resolv.conf | grep nameserver | head -1 | awk '{print $2}')
    
    # Create network configuration based on target distro
    case "$SELECTED_DISTRO" in
        ubuntu|debian|proxmox)
            # Debian-style networking
            cat > "${target}/etc/network/interfaces" << EOF
auto lo
iface lo inet loopback

auto ${PRIMARY_INTERFACE}
iface ${PRIMARY_INTERFACE} inet static
    address ${ip_addr}/${netmask}
    gateway ${gateway}
    dns-nameservers ${dns}
EOF
            ;;
        fedora|rocky)
            # RHEL-style networking (NetworkManager)
            local connection_name="System ${PRIMARY_INTERFACE}"
            mkdir -p "${target}/etc/NetworkManager/system-connections"
            cat > "${target}/etc/NetworkManager/system-connections/${connection_name}.nmconnection" << EOF
[connection]
id=${connection_name}
type=ethernet
interface-name=${PRIMARY_INTERFACE}

[ipv4]
method=manual
addresses=${ip_addr}/${netmask}
gateway=${gateway}
dns=${dns}

[ipv6]
method=disabled
EOF
            chmod 600 "${target}/etc/NetworkManager/system-connections/${connection_name}.nmconnection"
            ;;
        arch)
            # systemd-networkd
            cat > "${target}/etc/systemd/network/20-wired.network" << EOF
[Match]
Name=${PRIMARY_INTERFACE}

[Network]
Address=${ip_addr}/${netmask}
Gateway=${gateway}
DNS=${dns}
EOF
            ;;
        alpine)
            # Alpine OpenRC
            cat > "${target}/etc/network/interfaces" << EOF
auto lo
iface lo inet loopback

auto ${PRIMARY_INTERFACE}
iface ${PRIMARY_INTERFACE} inet static
    address ${ip_addr}
    netmask ${netmask}
    gateway ${gateway}
EOF
            echo "nameserver ${dns}" > "${target}/etc/resolv.conf"
            ;;
    esac
    
    print_success "Network configuration saved"
    print_info "IP: ${ip_addr}/${netmask}"
    print_info "Gateway: ${gateway}"
    print_info "DNS: ${dns}"
}

#===================================================================================
# CHROOT HELPERS
#===================================================================================

setup_chroot() {
    local target="$1"
    
    print_step "Setting up chroot environment..."
    
    mount --bind /dev "${target}/dev"
    mount --bind /dev/pts "${target}/dev/pts"
    mount --bind /proc "${target}/proc"
    mount --bind /sys "${target}/sys"
    
    # Copy DNS configuration
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

#===================================================================================
# USER CONFIGURATION
#===================================================================================

create_user() {
    local target="$1"
    local username="$2"
    local password="$3"
    
    print_step "Creating user: ${username}"
    
    # Create user with appropriate groups
    run_chroot "$target" "useradd -m -s /bin/bash -G sudo,adm,cdrom,dip,plugdev '${username}' 2>/dev/null || \
                         useradd -m -s /bin/bash -G wheel,adm,cdrom,dip,plugdev '${username}' 2>/dev/null || \
                         useradd -m -s /bin/bash '${username}'"
    
    # Set password
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

configure_ssh() {
    local target="$1"
    local port="$2"
    local ssh_key="$3"
    local username="$4"
    
    print_step "Configuring SSH access..."
    
    mkdir -p "${target}/etc/ssh"
    mkdir -p "${target}/home/${username}/.ssh"
    
    # Configure sshd
    cat > "${target}/etc/ssh/sshd_config.d/remote-reinstall.conf" << EOF
Port ${port}
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
EOF
    
    # Add SSH key if provided
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
    
    print_step "Configuring /etc/fstab..."
    
    local root_uuid=$(blkid -s UUID -o value "$ROOT_PARTITION")
    local boot_uuid=""
    
    [[ -n "$BOOT_PARTITION" ]] && boot_uuid=$(blkid -s UUID -o value "$BOOT_PARTITION")
    
    cat > "${target}/etc/fstab" << EOF
UUID=${root_uuid}  /        ext4   defaults,noatime  0 1
EOF
    
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
        
        # Also create a fallback EFI entry
        mkdir -p "${target}/boot/efi/EFI/BOOT"
        cp "${target}/boot/efi/EFI/GRUB/grubx64.efi" "${target}/boot/efi/EFI/BOOT/BOOTX64.EFI" 2>/dev/null || true
    else
        run_chroot "$target" "grub-install ${disk}"
    fi
    
    run_chroot "$target" "grub-mkconfig -o /boot/grub/grub.cfg" 2>/dev/null || \
    run_chroot "$target" "grub2-mkconfig -o /boot/grub2/grub.cfg" 2>/dev/null
    
    print_success "GRUB installed"
}

#===================================================================================
# DISTRIBUTION INSTALLERS
#===================================================================================

install_debian() {
    local codename
    case "$SELECTED_VERSION" in
        12) codename="bookworm" ;;
        11) codename="bullseye" ;;
        *) die "Unsupported Debian version: ${SELECTED_VERSION}" ;;
    esac
    
    print_step "Installing Debian ${SELECTED_VERSION} (${codename})..."
    print_info "This may take 10-20 minutes..."
    
    # Bootstrap Debian
    debootstrap --arch=amd64 --variant=minbase "$codename" "$MOUNT_ROOT" http://deb.debian.org/debian/
    
    print_success "Base system installed"
    
    # Configure APT
    cat > "${MOUNT_ROOT}/etc/apt/sources.list" << EOF
deb http://deb.debian.org/debian ${codename} main contrib non-free-firmware
deb http://deb.debian.org/debian ${codename}-updates main contrib non-free-firmware
deb http://security.debian.org/debian-security ${codename}-security main contrib non-free-firmware
EOF
    
    setup_chroot "$MOUNT_ROOT"
    
    print_step "Installing kernel and essential packages..."
    run_chroot "$MOUNT_ROOT" "apt-get update"
    run_chroot "$MOUNT_ROOT" "DEBIAN_FRONTEND=noninteractive apt-get install -y \
        linux-image-amd64 grub-efi-amd64 grub-pc openssh-server sudo \
        systemd systemd-sysv locales tzdata ifupdown isc-dhcp-client iproute2 \
        --no-install-recommends"
    
    # Configure locale
    run_chroot "$MOUNT_ROOT" "sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen"
    run_chroot "$MOUNT_ROOT" "locale-gen en_US.UTF-8"
    echo "LANG=en_US.UTF-8" > "${MOUNT_ROOT}/etc/default/locale"
    
    # Configure timezone
    run_chroot "$MOUNT_ROOT" "ln -sf /usr/share/zoneinfo/UTC /etc/localtime"
    
    # Configure system
    set_hostname "$MOUNT_ROOT" "$HOSTNAME"
    create_user "$MOUNT_ROOT" "$USERNAME" "$PASSWORD"
    save_network_config "$MOUNT_ROOT"
    configure_ssh "$MOUNT_ROOT" "$SSH_PORT" "$SSH_KEY" "$USERNAME"
    configure_fstab "$MOUNT_ROOT"
    install_grub "$MOUNT_ROOT" "$INSTALL_DISK"
    
    # Enable SSH
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
    
    # Bootstrap Ubuntu
    debootstrap --arch=amd64 --variant=minbase "$codename" "$MOUNT_ROOT" http://archive.ubuntu.com/ubuntu/
    
    print_success "Base system installed"
    
    # Configure APT
    cat > "${MOUNT_ROOT}/etc/apt/sources.list" << EOF
deb http://archive.ubuntu.com/ubuntu ${codename} main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu ${codename}-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu ${codename}-security main restricted universe multiverse
EOF
    
    setup_chroot "$MOUNT_ROOT"
    
    print_step "Installing kernel and essential packages..."
    run_chroot "$MOUNT_ROOT" "apt-get update"
    run_chroot "$MOUNT_ROOT" "DEBIAN_FRONTEND=noninteractive apt-get install -y \
        linux-image-generic grub-efi-amd64 grub-pc openssh-server sudo \
        systemd systemd-sysv locales tzdata netplan.io \
        --no-install-recommends"
    
    # Configure locale and timezone
    run_chroot "$MOUNT_ROOT" "sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen"
    run_chroot "$MOUNT_ROOT" "locale-gen en_US.UTF-8"
    echo "LANG=en_US.UTF-8" > "${MOUNT_ROOT}/etc/default/locale"
    run_chroot "$MOUNT_ROOT" "ln -sf /usr/share/zoneinfo/UTC /etc/localtime"
    
    # Configure system
    set_hostname "$MOUNT_ROOT" "$HOSTNAME"
    create_user "$MOUNT_ROOT" "$USERNAME" "$PASSWORD"
    
    # Netplan configuration
    local ip_addr netmask gateway
    ip_addr=$(ip -4 addr show "$PRIMARY_INTERFACE" | grep inet | awk '{print $2}' | cut -d/ -f1)
    netmask=$(ip -4 addr show "$PRIMARY_INTERFACE" | grep inet | awk '{print $2}' | cut -d/ -f2)
    gateway=$(ip route | grep default | awk '{print $3}')
    
    mkdir -p "${MOUNT_ROOT}/etc/netplan"
    cat > "${MOUNT_ROOT}/etc/netplan/01-netcfg.yaml" << EOF
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
EOF
    
    configure_ssh "$MOUNT_ROOT" "$SSH_PORT" "$SSH_KEY" "$USERNAME"
    configure_fstab "$MOUNT_ROOT"
    install_grub "$MOUNT_ROOT" "$INSTALL_DISK"
    
    run_chroot "$MOUNT_ROOT" "systemctl enable ssh"
    
    cleanup_chroot "$MOUNT_ROOT"
    
    print_success "Ubuntu ${SELECTED_VERSION} installation complete!"
}

install_alpine() {
    print_step "Installing Alpine ${SELECTED_VERSION}..."
    
    # Download Alpine minirootfs
    local alpine_version="${SELECTED_VERSION}"
    [[ "$alpine_version" == "edge" ]] && alpine_version="latest-stable"
    
    local rootfs_url="https://dl-cdn.alpinelinux.org/alpine/v${alpine_version}/releases/x86_64/alpine-minirootfs-${alpine_version}.0-x86_64.tar.gz"
    
    print_info "Downloading Alpine rootfs..."
    wget -q -O /tmp/alpine-rootfs.tar.gz "$rootfs_url" || \
        curl -sL -o /tmp/alpine-rootfs.tar.gz "$rootfs_url"
    
    # Extract rootfs
    tar -xzf /tmp/alpine-rootfs.tar.gz -C "$MOUNT_ROOT"
    
    print_success "Base system installed"
    
    # Configure APK repositories
    cat > "${MOUNT_ROOT}/etc/apk/repositories" << EOF
https://dl-cdn.alpinelinux.org/alpine/v${SELECTED_VERSION}/main
https://dl-cdn.alpinelinux.org/alpine/v${SELECTED_VERSION}/community
EOF
    
    setup_chroot "$MOUNT_ROOT"
    
    print_step "Installing kernel and essential packages..."
    run_chroot "$MOUNT_ROOT" "apk update"
    run_chroot "$MOUNT_ROOT" "apk add linux-lts grub-efi grub-bios openssh sudo openrc \
        e2fsprogs sfdisk util-linux"
    
    # Configure system
    set_hostname "$MOUNT_ROOT" "$HOSTNAME"
    create_user "$MOUNT_ROOT" "$USERNAME" "$PASSWORD"
    save_network_config "$MOUNT_ROOT"
    configure_ssh "$MOUNT_ROOT" "$SSH_PORT" "$SSH_KEY" "$USERNAME"
    configure_fstab "$MOUNT_ROOT"
    install_grub "$MOUNT_ROOT" "$INSTALL_DISK"
    
    # Enable services
    run_chroot "$MOUNT_ROOT" "rc-update add sshd default"
    run_chroot "$MOUNT_ROOT" "rc-update add networking boot"
    
    cleanup_chroot "$MOUNT_ROOT"
    
    print_success "Alpine ${SELECTED_VERSION} installation complete!"
}

#===================================================================================
# MAIN FLOW
#===================================================================================

show_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
 ██████╗ ███████╗██████╗  ██████╗ ███████╗██╗     ███████╗███████╗ ██████╗
 ██╔══██╗██╔════╝██╔══██╗██╔════╝ ██╔════╝██║     ██╔════╝██╔════╝██╔════╝
 ██████╔╝█████╗  ██████╔╝██║  ███╗█████╗  ██║     █████╗  ███████╗██║     
 ██╔══██╗██╔══╝  ██╔══██╗██║   ██║██╔══╝  ██║     ██╔══╝  ╚════██║██║     
 ██║  ██║███████╗██║  ██║╚██████╔╝███████╗███████╗███████╗███████║╚██████╗
 ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚══════╝╚══════╝╚══════╝ ╚═════╝
EOF
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
    
    # Initialize log
    echo "=== RAM Installer Started at $(date) ===" > "$LOG_FILE"
    
    # Load configuration
    load_config
    
    # Partition the disk
    partition_disk "$INSTALL_DISK"
    
    # Mount partitions
    mount_partitions
    
    # Run the appropriate installer
    case "$SELECTED_DISTRO" in
        debian)
            install_debian
            ;;
        ubuntu)
            install_ubuntu
            ;;
        alpine)
            install_alpine
            ;;
        *)
            die "Unsupported distribution: ${SELECTED_DISTRO}"
            ;;
    esac
    
    # Unmount
    unmount_partitions
    
    # Show completion and reboot
    show_completion
    
    print_info "Rebooting in 5 seconds..."
    sleep 5
    
    print_info "Rebooting now..."
    reboot -f
}

# Run main
main "$@"
