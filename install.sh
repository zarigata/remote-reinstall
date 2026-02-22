#!/bin/bash
#
# ██████╗ ███████╗██████╗  ██████╗ ███████╗██╗     ███████╗███████╗ ██████╗
# ██╔══██╗██╔════╝██╔══██╗██╔════╝ ██╔════╝██║     ██╔════╝██╔════╝██╔════╝
# ██████╔╝█████╗  ██████╔╝██║  ███╗█████╗  ██║     █████╗  ███████╗██║     
# ██╔══██╗██╔══╝  ██╔══██╗██║   ██║██╔══╝  ██║     ██╔══╝  ╚════██║██║     
# ██║  ██║███████╗██║  ██║╚██████╔╝███████╗███████╗███████╗███████║╚██████╗
# ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚══════╝╚══════╝╚══════╝ ╚═════╝
#
# Remote Linux Reinstaller - Transform any Linux machine into a fresh distro
# Repository: https://github.com/zarigata/remote-reinstall
# License: MIT
#
# Usage: curl -fsSL https://raw.githubusercontent.com/zarigata/remote-reinstall/main/install.sh | bash
#

set -o pipefail

#===================================================================================
# GLOBAL VARIABLES
#===================================================================================
VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
DISTROS_DIR="${SCRIPT_DIR}/distros"
CONFIGS_DIR="${SCRIPT_DIR}/configs"
LOG_FILE="/tmp/remote-reinstall-$(date +%Y%m%d_%H%M%S).log"
SELECTED_DISTRO=""
SELECTED_VERSION=""
INSTALL_DISK=""
HOSTNAME=""
USERNAME=""
PASSWORD=""
SSH_PORT=""
SSH_KEY=""
PRESERVE_SSH=true
VERBOSE=false
FORCE=false
UI_BACKEND=""

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

#===================================================================================
# UTILITY FUNCTIONS
#===================================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

print_banner() {
    clear
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
    echo -e "${WHITE}  Remote Linux Reinstaller v${VERSION}${NC}"
    echo -e "${YELLOW}  Transform any Linux machine into a fresh distribution${NC}"
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
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
    echo -e "${YELLOW}Installation aborted. Check log at: ${LOG_FILE}${NC}"
    exit 1
}

#===================================================================================
# DEPENDENCY CHECKS
#===================================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        echo ""
        echo "Try: curl -fsSL ... | sudo bash"
        exit 1
    fi
}

detect_system() {
    print_step "Detecting system information..."
    
    # Detect distribution
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        CURRENT_DISTRO="${ID:-unknown}"
        CURRENT_VERSION="${VERSION_ID:-unknown}"
    else
        CURRENT_DISTRO="unknown"
        CURRENT_VERSION="unknown"
    fi
    
    # Detect architecture
    ARCH=$(uname -m)
    
    # Detect boot mode
    if [[ -d /sys/firmware/efi ]]; then
        BOOT_MODE="UEFI"
    else
        BOOT_MODE="BIOS"
    fi
    
    # Get network info
    PRIMARY_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
    PRIMARY_IP=$(ip -4 addr show "$PRIMARY_INTERFACE" | grep inet | awk '{print $2}' | cut -d/ -f1)
    
    print_info "Current OS: ${CURRENT_DISTRO} ${CURRENT_VERSION}"
    print_info "Architecture: ${ARCH}"
    print_info "Boot mode: ${BOOT_MODE}"
    print_info "Primary IP: ${PRIMARY_IP}"
    print_info "Network interface: ${PRIMARY_INTERFACE}"
}

check_dependencies() {
    print_step "Checking dependencies..."
    
    local missing=()
    local required=("curl" "wget" "parted" "lsblk")
    
    for cmd in "${required[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    
    # Check for UI backends
    if command -v whiptail &> /dev/null; then
        UI_BACKEND="whiptail"
    elif command -v dialog &> /dev/null; then
        UI_BACKEND="dialog"
    else
        UI_BACKEND="text"
    fi
    
    print_info "UI Backend: ${UI_BACKEND}"
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_warning "Missing dependencies: ${missing[*]}"
        print_info "Attempting to install missing dependencies..."
        install_dependencies "${missing[@]}"
    fi
    
    print_success "All dependencies satisfied"
}

install_dependencies() {
    local pkgs=("$@")
    
    if command -v apt-get &> /dev/null; then
        apt-get update -qq
        apt-get install -y -qq "${pkgs[@]}" whiptail
    elif command -v dnf &> /dev/null; then
        dnf install -y "${pkgs[@]}" newt
    elif command -v yum &> /dev/null; then
        yum install -y "${pkgs[@]}" newt
    elif command -v pacman &> /dev/null; then
        pacman -Sy --noconfirm "${pkgs[@]}" libnewt
    elif command -v apk &> /dev/null; then
        apk add "${pkgs[@]}" newt
    else
        die "Unsupported package manager. Please install: ${pkgs[*]}"
    fi
    
    # Re-check UI backend after install
    if command -v whiptail &> /dev/null; then
        UI_BACKEND="whiptail"
    elif command -v dialog &> /dev/null; then
        UI_BACKEND="dialog"
    fi
}

#===================================================================================
# UI FUNCTIONS
#===================================================================================

show_welcome() {
    print_banner
    
    if [[ "$UI_BACKEND" == "whiptail" ]] || [[ "$UI_BACKEND" == "dialog" ]]; then
        local msg="${WHITE}Welcome to Remote Linux Reinstaller!${NC}\n\n"
        msg+="This tool will completely replace your current operating system\n"
        msg+="with a fresh installation of your chosen distribution.\n\n"
        msg+="${YELLOW}⚠ WARNING: This will ERASE ALL DATA on the selected disk!${NC}\n\n"
        msg+="${CYAN}Features:${NC}\n"
        msg+="  • Preserves SSH access throughout the process\n"
        msg+="  • Pre-configures user accounts and SSH keys\n"
        msg+="  • Supports multiple distributions\n"
        msg+="  • Fully automated, no physical access needed\n\n"
        msg+="${GREEN}Press Enter to continue...${NC}"
        
        echo -e "$msg"
        read -r
    else
        $UI_BACKEND --title "Remote Linux Reinstaller" --msgbox \
            "Welcome to Remote Linux Reinstaller!\n\nThis tool will completely replace your current operating system with a fresh installation of your chosen distribution.\n\n⚠ WARNING: This will ERASE ALL DATA on the selected disk!\n\nFeatures:\n• Preserves SSH access throughout the process\n• Pre-configures user accounts and SSH keys\n• Supports multiple distributions\n• Fully automated, no physical access needed" 20 70
    fi
}

select_distro() {
    print_step "Select target distribution..."
    
    local distros=(
        "ubuntu"    "Ubuntu LTS         (User-friendly, great support)"
        "debian"    "Debian Stable      (Rock-solid stability)"
        "proxmox"   "Proxmox VE         (Virtualization platform)"
        "fedora"    "Fedora Server      (Cutting-edge features)"
        "rocky"     "Rocky Linux        (RHEL-compatible, enterprise)"
        "arch"      "Arch Linux         (Rolling release, DIY)"
        "alpine"    "Alpine Linux       (Lightweight, security-focused)"
    )
    
    if [[ "$UI_BACKEND" == "whiptail" ]]; then
        SELECTED_DISTRO=$(whiptail --title "Select Distribution" \
            --menu "\nChoose the Linux distribution to install:\n" 20 70 7 \
            "${distros[@]}" 3>&1 1>&2 2>&3)
    elif [[ "$UI_BACKEND" == "dialog" ]]; then
        SELECTED_DISTRO=$(dialog --title "Select Distribution" \
            --menu "\nChoose the Linux distribution to install:\n" 20 70 7 \
            "${distros[@]}" 3>&1 1>&2 2>&3)
    else
        # Text-based fallback
        echo ""
        echo "Available distributions:"
        echo ""
        local i=1
        while [[ $i -lt ${#distros[@]} ]]; do
            printf "  ${CYAN}%d)${NC} %-16s %s\n" "$((i/2+1))" "${distros[$i-1]}" "${distros[$i]}"
            ((i+=2))
        done
        echo ""
        read -rp "Enter selection [1-7]: " choice
        SELECTED_DISTRO="${distros[$((choice*2-2))]}"
    fi
    
    if [[ -z "$SELECTED_DISTRO" ]]; then
        die "No distribution selected"
    fi
    
    print_success "Selected: ${SELECTED_DISTRO}"
}

select_version() {
    print_step "Select version..."
    
    local versions=()
    
    case "$SELECTED_DISTRO" in
        ubuntu)
            versions=(
                "24.04" "Ubuntu 24.04 LTS (Noble Numbat) - Latest LTS"
                "22.04" "Ubuntu 22.04 LTS (Jammy Jellyfish) - Previous LTS"
                "20.04" "Ubuntu 20.04 LTS (Focal Fossa) - Legacy LTS"
            )
            ;;
        debian)
            versions=(
                "12"    "Debian 12 (Bookworm) - Current Stable"
                "11"    "Debian 11 (Bullseye) - Old Stable"
            )
            ;;
        proxmox)
            versions=(
                "8"     "Proxmox VE 8.x (Based on Debian 12)"
                "7"     "Proxmox VE 7.x (Based on Debian 11)"
            )
            ;;
        fedora)
            versions=(
                "40"    "Fedora 40 - Latest"
                "39"    "Fedora 39 - Previous"
            )
            ;;
        rocky)
            versions=(
                "9"     "Rocky Linux 9 (RHEL 9 compatible)"
                "8"     "Rocky Linux 8 (RHEL 8 compatible)"
            )
            ;;
        arch)
            versions=(
                "latest" "Arch Linux (Rolling - Latest)"
            )
            ;;
        alpine)
            versions=(
                "3.19"  "Alpine 3.19 - Latest Stable"
                "3.18"  "Alpine 3.18 - Previous Stable"
                "edge"  "Alpine Edge - Rolling"
            )
            ;;
    esac
    
    if [[ "$UI_BACKEND" == "whiptail" ]]; then
        SELECTED_VERSION=$(whiptail --title "Select ${SELECTED_DISTRO^} Version" \
            --menu "\nChoose the version to install:\n" 15 60 5 \
            "${versions[@]}" 3>&1 1>&2 2>&3)
    elif [[ "$UI_BACKEND" == "dialog" ]]; then
        SELECTED_VERSION=$(dialog --title "Select ${SELECTED_DISTRO^} Version" \
            --menu "\nChoose the version to install:\n" 15 60 5 \
            "${versions[@]}" 3>&1 1>&2 2>&3)
    else
        echo ""
        echo "Available versions for ${SELECTED_DISTRO^}:"
        echo ""
        local i=1
        while [[ $i -lt ${#versions[@]} ]]; do
            printf "  ${CYAN}%d)${NC} %s\n" "$((i/2+1))" "${versions[$i]}"
            ((i+=2))
        done
        echo ""
        read -rp "Enter selection: " choice
        SELECTED_VERSION="${versions[$((choice*2-2))]}"
    fi
    
    if [[ -z "$SELECTED_VERSION" ]]; then
        die "No version selected"
    fi
    
    print_success "Selected version: ${SELECTED_VERSION}"
}

select_disk() {
    print_step "Select installation disk..."
    
    local disks=()
    while IFS= read -r line; do
        local name size type model
        name=$(echo "$line" | awk '{print $1}')
        size=$(echo "$line" | awk '{print $2}')
        type=$(echo "$line" | awk '{print $3}')
        model=$(lsblk -dno MODEL "/dev/$name" 2>/dev/null | xargs)
        [[ -z "$model" ]] && model="Unknown"
        disks+=("$name" "${size} ${type} - ${model}")
    done < <(lsblk -dno NAME,SIZE,TYPE | grep disk)
    
    if [[ ${#disks[@]} -eq 0 ]]; then
        die "No disks found"
    fi
    
    if [[ "$UI_BACKEND" == "whiptail" ]]; then
        INSTALL_DISK=$(whiptail --title "Select Installation Disk" \
            --menu "\n⚠ WARNING: ALL DATA on selected disk will be ERASED!\n\nChoose the disk to install to:\n" 18 60 5 \
            "${disks[@]}" 3>&1 1>&2 2>&3)
    elif [[ "$UI_BACKEND" == "dialog" ]]; then
        INSTALL_DISK=$(dialog --title "Select Installation Disk" \
            --menu "\n⚠ WARNING: ALL DATA on selected disk will be ERASED!\n\nChoose the disk to install to:\n" 18 60 5 \
            "${disks[@]}" 3>&1 1>&2 2>&3)
    else
        echo ""
        echo "Available disks:"
        echo ""
        local i=1
        while [[ $i -lt ${#disks[@]} ]]; do
            printf "  ${CYAN}%d)${NC} /dev/%-8s %s\n" "$((i/2+1))" "${disks[$i-1]}" "${disks[$i]}"
            ((i+=2))
        done
        echo ""
        read -rp "Enter selection: " choice
        INSTALL_DISK="${disks[$((choice*2-2))]}"
    fi
    
    if [[ -z "$INSTALL_DISK" ]]; then
        die "No disk selected"
    fi
    
    INSTALL_DISK="/dev/${INSTALL_DISK}"
    print_success "Selected disk: ${INSTALL_DISK}"
}

configure_user() {
    print_step "Configure user account..."
    
    # Hostname
    if [[ "$UI_BACKEND" == "whiptail" ]]; then
        HOSTNAME=$(whiptail --title "Set Hostname" --inputbox "\nEnter hostname for the new system:" 10 50 "server" 3>&1 1>&2 2>&3)
    elif [[ "$UI_BACKEND" == "dialog" ]]; then
        HOSTNAME=$(dialog --title "Set Hostname" --inputbox "\nEnter hostname for the new system:" 10 50 "server" 3>&1 1>&2 2>&3)
    else
        read -rp "Enter hostname [server]: " HOSTNAME
        [[ -z "$HOSTNAME" ]] && HOSTNAME="server"
    fi
    
    # Username
    if [[ "$UI_BACKEND" == "whiptail" ]]; then
        USERNAME=$(whiptail --title "Create User" --inputbox "\nEnter username for the primary user:" 10 50 "admin" 3>&1 1>&2 2>&3)
    elif [[ "$UI_BACKEND" == "dialog" ]]; then
        USERNAME=$(dialog --title "Create User" --inputbox "\nEnter username for the primary user:" 10 50 "admin" 3>&1 1>&2 2>&3)
    else
        read -rp "Enter username [admin]: " USERNAME
        [[ -z "$USERNAME" ]] && USERNAME="admin"
    fi
    
    # Password
    if [[ "$UI_BACKEND" == "whiptail" ]]; then
        PASSWORD=$(whiptail --title "Set Password" --passwordbox "\nEnter password for ${USERNAME}:" 10 50 3>&1 1>&2 2>&3)
        local pass_confirm
        pass_confirm=$(whiptail --title "Confirm Password" --passwordbox "\nConfirm password:" 10 50 3>&1 1>&2 2>&3)
        if [[ "$PASSWORD" != "$pass_confirm" ]]; then
            die "Passwords do not match"
        fi
    elif [[ "$UI_BACKEND" == "dialog" ]]; then
        PASSWORD=$(dialog --title "Set Password" --passwordbox "\nEnter password for ${USERNAME}:" 10 50 3>&1 1>&2 2>&3)
        local pass_confirm
        pass_confirm=$(dialog --title "Confirm Password" --passwordbox "\nConfirm password:" 10 50 3>&1 1>&2 2>&3)
        if [[ "$PASSWORD" != "$pass_confirm" ]]; then
            die "Passwords do not match"
        fi
    else
        read -rsp "Enter password: " PASSWORD
        echo
        local pass_confirm
        read -rsp "Confirm password: " pass_confirm
        echo
        if [[ "$PASSWORD" != "$pass_confirm" ]]; then
            die "Passwords do not match"
        fi
    fi
    
    # SSH Key (optional)
    if [[ "$UI_BACKEND" == "whiptail" ]]; then
        if whiptail --title "SSH Key" --yesno "\nWould you like to add an SSH public key for authentication?" 10 50; then
            SSH_KEY=$(whiptail --title "SSH Public Key" --inputbox "\nPaste your SSH public key:" 10 70 3>&1 1>&2 2>&3)
        fi
    elif [[ "$UI_BACKEND" == "dialog" ]]; then
        if dialog --title "SSH Key" --yesno "\nWould you like to add an SSH public key for authentication?" 10 50; then
            SSH_KEY=$(dialog --title "SSH Public Key" --inputbox "\nPaste your SSH public key:" 10 70 3>&1 1>&2 2>&3)
        fi
    else
        read -rp "Add SSH public key? (y/N): " add_key
        if [[ "$add_key" =~ ^[Yy]$ ]]; then
            read -rp "Paste your SSH public key: " SSH_KEY
        fi
    fi
    
    # SSH Port
    if [[ "$UI_BACKEND" == "whiptail" ]]; then
        SSH_PORT=$(whiptail --title "SSH Port" --inputbox "\nEnter SSH port:" 10 50 "22" 3>&1 1>&2 2>&3)
    elif [[ "$UI_BACKEND" == "dialog" ]]; then
        SSH_PORT=$(dialog --title "SSH Port" --inputbox "\nEnter SSH port:" 10 50 "22" 3>&1 1>&2 2>&3)
    else
        read -rp "SSH port [22]: " SSH_PORT
        [[ -z "$SSH_PORT" ]] && SSH_PORT="22"
    fi
    
    print_success "User configured: ${USERNAME}"
    print_success "Hostname: ${HOSTNAME}"
    print_success "SSH Port: ${SSH_PORT}"
    [[ -n "$SSH_KEY" ]] && print_success "SSH Key: Configured"
}

confirm_installation() {
    print_step "Review installation settings..."
    
    local summary="
╔══════════════════════════════════════════════════════════════════╗
║                    INSTALLATION SUMMARY                          ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                  ║
║  Distribution:    ${SELECTED_DISTRO^} ${SELECTED_VERSION}
║  Target Disk:     ${INSTALL_DISK}
║  Hostname:        ${HOSTNAME}
║  Username:        ${USERNAME}
║  SSH Port:        ${SSH_PORT}
║  SSH Key:         $([ -n "$SSH_KEY" ] && echo "Yes" || echo "No")
║  Boot Mode:       ${BOOT_MODE}
║                                                                  ║
╠══════════════════════════════════════════════════════════════════╣
║  ⚠ WARNING: This will PERMANENTLY DELETE ALL DATA               ║
║             on ${INSTALL_DISK}
║                                                                  ║
║  Current IP: ${PRIMARY_IP} (will be preserved)
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
"
    
    if [[ "$UI_BACKEND" == "whiptail" ]]; then
        if ! whiptail --title "Confirm Installation" --yesno "$summary" 22 70 --defaultno; then
            die "Installation cancelled by user"
        fi
    elif [[ "$UI_BACKEND" == "dialog" ]]; then
        if ! dialog --title "Confirm Installation" --yesno "$summary" 22 70 --defaultno; then
            die "Installation cancelled by user"
        fi
    else
        echo -e "$summary"
        read -rp "Proceed with installation? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            die "Installation cancelled by user"
        fi
    fi
    
    print_success "Installation confirmed"
}

#===================================================================================
# MAIN INSTALLATION FLOW
#===================================================================================

run_installer() {
    print_step "Starting ${SELECTED_DISTRO^} installation..."
    print_info "This may take a while. Do not close this terminal!"
    print_info "Log file: ${LOG_FILE}"
    
    # Source the distro-specific installer
    local installer_script="${DISTROS_DIR}/${SELECTED_DISTRO}.sh"
    
    if [[ ! -f "$installer_script" ]]; then
        die "Installer not found for ${SELECTED_DISTRO}: ${installer_script}"
    fi
    
    # Export configuration for the installer
    export INSTALL_DISK SELECTED_VERSION HOSTNAME USERNAME PASSWORD SSH_PORT SSH_KEY
    export BOOT_MODE ARCH PRIMARY_INTERFACE PRIMARY_IP LOG_FILE
    
    # Run the installer
    source "$installer_script"
    
    # Run the main installation function
    install_"${SELECTED_DISTRO}"
}

#===================================================================================
# POST-INSTALLATION
#===================================================================================

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
    echo -e "${GREEN}════════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

#===================================================================================
# ENTRY POINT
#===================================================================================

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--distro)
                SELECTED_DISTRO="$2"
                shift 2
                ;;
            -v|--version)
                SELECTED_VERSION="$2"
                shift 2
                ;;
            --disk)
                INSTALL_DISK="$2"
                shift 2
                ;;
            --hostname)
                HOSTNAME="$2"
                shift 2
                ;;
            --username)
                USERNAME="$2"
                shift 2
                ;;
            --password)
                PASSWORD="$2"
                shift 2
                ;;
            --ssh-port)
                SSH_PORT="$2"
                shift 2
                ;;
            --ssh-key)
                SSH_KEY="$2"
                shift 2
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Initialize log
    echo "=== Remote Reinstall Log Started at $(date) ===" > "$LOG_FILE"
    
    # Run checks
    check_root
    check_dependencies
    detect_system
    
    # Interactive or non-interactive mode
    if [[ -n "$SELECTED_DISTRO" && -n "$SELECTED_VERSION" && -n "$INSTALL_DISK" ]]; then
        # Non-interactive mode (all parameters provided)
        print_banner
        print_info "Running in non-interactive mode"
        [[ -z "$HOSTNAME" ]] && HOSTNAME="server"
        [[ -z "$USERNAME" ]] && USERNAME="admin"
        [[ -z "$SSH_PORT" ]] && SSH_PORT="22"
    else
        # Interactive mode
        show_welcome
        select_distro
        select_version
        select_disk
        configure_user
        confirm_installation
    fi
    
    # Run the installer
    run_installer
    
    # Show completion message
    show_completion
}

show_help() {
    cat << EOF
Usage: install.sh [OPTIONS]

Remote Linux Reinstaller - Transform any Linux machine into a fresh distribution

Options:
  -d, --distro DISTRO      Distribution to install (ubuntu, debian, proxmox, fedora, rocky, arch, alpine)
  -v, --version VERSION    Version to install (e.g., 24.04 for Ubuntu, 12 for Debian)
  --disk DISK              Target disk (e.g., /dev/sda)
  --hostname NAME          Set hostname
  --username USER          Primary username
  --password PASS          Password for the user
  --ssh-port PORT          SSH port (default: 22)
  --ssh-key "KEY"          SSH public key for authentication
  --force                  Skip confirmation
  --verbose                Enable verbose output
  -h, --help               Show this help message

Examples:
  # Interactive mode
  curl -fsSL https://raw.githubusercontent.com/.../install.sh | bash

  # Non-interactive Ubuntu 24.04 installation
  curl -fsSL ... | bash -s -- -d ubuntu -v 24.04 --disk /dev/sda \\
    --hostname myserver --username admin --password secret \\
    --ssh-key "ssh-rsa AAAA..."

EOF
}

# Run main
main "$@"
