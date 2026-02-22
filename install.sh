#!/bin/bash
#
# ██████╗ ███████╗██████╗  ██████╗ ███████╗██╗     ███████╗███████╗ ██████╗
# ██╔══██╗██╔════╝██╔══██╗██╔════╝ ██╔════╝██║     ██╔════╝██╔════╝██╔════╝
# ██████╔╝█████╗  ██████╔╝██║  ███╗█████╗  ██║     █████╗  ███████╗██║     
# ██╔══██╗██╔══╝  ██╔══██╗██║   ██║██╔══╝  ██║     ██╔══╝  ╚════██║██║     
# ██║  ██║███████╗██║  ██║╚██████╔╝███████╗███████╗███████╗███████║╚██████╗
# ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚══════╝╚══════╝╚══════╝ ╚═════╝
#
#  ███████╗ █████╗ ███████╗███████╗██╗   ██╗ ██████╗
#  ██╔════╝██╔══██╗██╔════╝██╔════╝╚██╗ ██╔╝██╔════╝
#  █████╗  ███████║███████╗█████╗   ╚████╔╝ ██║  ███╗
#  ██╔══╝  ██╔══██║╚════██║██╔══╝    ╚██╔╝  ██║   ██║
#  ███████╗██║  ██║███████║███████╗   ██║   ╚██████╔╝
#  ╚══════╝╚═╝  ╚═╝╚══════╝╚══════╝   ╚═╝    ╚═════╝
#
# ███████╗ ██████╗ █████╗  ██████╗███████╗██████╗ 
# ██╔════╝██╔════╝██╔══██╗██╔════╝██╔════╝██╔══██╗
# ███████╗██║     ███████║██║     █████╗  ██████╔╝
# ╚════██║██║     ██╔══██║██║     ██╔══╝  ██╔══██╗
# ███████║╚██████╗██║  ██║╚██████╗███████╗██║  ██║
# ╚══════╝ ╚═════╝╚═╝  ╚═╝ ╚═════╝╚══════╝╚═╝  ╚═╝
#
# Remote Linux Reinstaller - by Zarigata | FeverDream
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
 ███████╗ █████╗ ███████╗███████╗██╗   ██╗ ██████╗
 ██╔════╝██╔══██╗██╔════╝██╔════╝╚██╗ ██╔╝██╔════╝
 █████╗  ███████║███████╗█████╗   ╚████╔╝ ██║  ███╗
 ██╔══╝  ██╔══██║╚════██║██╔══╝    ╚██╔╝  ██║   ██║
 ███████╗██║  ██║███████║███████╗   ██║   ╚██████╔╝
 ╚══════╝╚═╝  ╚═╝╚══════╝╚══════╝   ╚═╝    ╚═════╝

 ███████╗ ██████╗ █████╗  ██████╗███████╗██████╗ 
 ██╔════╝██╔════╝██╔══██╗██╔════╝██╔════╝██╔══██╗
 ███████╗██║     ███████║██║     █████╗  ██████╔╝
 ╚════██║██║     ██╔══██║██║     ██╔══╝  ██╔══██╗
 ███████║╚██████╗██║  ██║╚██████╗███████╗██║  ██║
 ╚══════╝ ╚═════╝╚═╝  ╚═╝ ╚═════╝╚══════╝╚═╝  ╚═╝
EOF
    echo -e "${NC}"
    echo -e "${WHITE}  Remote Linux Reinstaller v${VERSION}${NC}"
    echo -e "${MAGENTA}  by Zarigata${NC} ${WHITE}|${NC} ${CYAN}FeverDream${NC}"
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

ask() {
    local prompt="$1"
    local varname="$2"
    local result
    if [[ -t 0 ]]; then
        read -rp "$prompt" result
    else
        read -rp "$prompt" result < /dev/tty
    fi
    eval "$varname=\$result"
}

ask_secret() {
    local prompt="$1"
    local varname="$2"
    local result
    if [[ -t 0 ]]; then
        read -rsp "$prompt" result
    else
        read -rsp "$prompt" result < /dev/tty
    fi
    eval "$varname=\$result"
}

get_input() {
    local prompt="$1"
    local var_name="$2"
    local default="$3"
    local input
    
    if [[ -n "$default" ]]; then
        prompt="${prompt} [${default}]"
    fi
    
    if [[ -t 0 ]]; then
        read -rp "$prompt: " input
    else
        read -rp "$prompt: " input < /dev/tty
    fi
    
    input=$(echo "$input" | tr -d '[:space:]')
    
    if [[ -z "$input" && -n "$default" ]]; then
        input="$default"
    fi
    
    eval "$var_name=\"$input\""
}

get_password() {
    local prompt="$1"
    local var_name="$2"
    local input
    
    if [[ -t 0 ]]; then
        read -rsp "$prompt: " input
    else
        read -rsp "$prompt: " input < /dev/tty
    fi
    echo
    
    eval "$var_name=\"$input\""
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
    
    local distro_keys=(ubuntu debian proxmox fedora rocky arch alpine)
    local distro_names=(
        "Ubuntu LTS       - User-friendly, great support"
        "Debian Stable    - Rock-solid stability"
        "Proxmox VE       - Virtualization platform"
        "Fedora Server    - Cutting-edge features"
        "Rocky Linux      - RHEL-compatible, enterprise"
        "Arch Linux       - Rolling release, DIY"
        "Alpine Linux     - Lightweight, security-focused"
    )
    
    echo ""
    echo -e "${WHITE}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║${NC}              ${BOLD}Select Target Distribution${NC}                        ${WHITE}║${NC}"
    echo -e "${WHITE}╠══════════════════════════════════════════════════════════════════╣${NC}"
    
    local i=0
    for key in "${distro_keys[@]}"; do
        printf "${WHITE}║${NC}  ${GREEN}%d)${NC} %-65s ${WHITE}║${NC}\n" "$((i+1))" "${distro_names[$i]}"
        ((i++))
    done
    
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    while true; do
        if [[ -t 0 ]]; then
            read -rp "Enter your choice [1-7]: " choice
        elif [[ -e /dev/tty && -r /dev/tty ]]; then
            read -rp "Enter your choice [1-7]: " choice < /dev/tty
        else
            # Fallback: try to read from stdin even if not a tty
            read -rp "Enter your choice [1-7]: " choice || choice=""
        fi
        
        choice=$(echo "$choice" | tr -d '[:space:]')
        
        if [[ "$choice" =~ ^[1-7]$ ]]; then
            SELECTED_DISTRO="${distro_keys[$((choice-1))]}"
            break
        else
            print_error "Invalid selection. Please enter a number between 1 and 7."
        fi
    done
    
    if [[ -z "$SELECTED_DISTRO" ]]; then
        die "No distribution selected"
    fi
    
    print_success "Selected: ${SELECTED_DISTRO}"
}

select_version() {
    print_step "Select ${SELECTED_DISTRO^} version..."
    
    local version_keys=()
    local version_names=()
    
    case "$SELECTED_DISTRO" in
        ubuntu)
            version_keys=("24.04" "22.04" "20.04")
            version_names=(
                "Ubuntu 24.04 LTS (Noble Numbat) - Latest LTS"
                "Ubuntu 22.04 LTS (Jammy Jellyfish) - Previous LTS"
                "Ubuntu 20.04 LTS (Focal Fossa) - Legacy LTS"
            )
            ;;
        debian)
            version_keys=("12" "11")
            version_names=(
                "Debian 12 (Bookworm) - Current Stable"
                "Debian 11 (Bullseye) - Old Stable"
            )
            ;;
        proxmox)
            version_keys=("8" "7")
            version_names=(
                "Proxmox VE 8.x (Based on Debian 12)"
                "Proxmox VE 7.x (Based on Debian 11)"
            )
            ;;
        fedora)
            version_keys=("40" "39")
            version_names=(
                "Fedora 40 - Latest"
                "Fedora 39 - Previous"
            )
            ;;
        rocky)
            version_keys=("9" "8")
            version_names=(
                "Rocky Linux 9 (RHEL 9 compatible)"
                "Rocky Linux 8 (RHEL 8 compatible)"
            )
            ;;
        arch)
            version_keys=("latest")
            version_names=("Arch Linux (Rolling - Latest)")
            ;;
        alpine)
            version_keys=("3.19" "3.18" "edge")
            version_names=(
                "Alpine 3.19 - Latest Stable"
                "Alpine 3.18 - Previous Stable"
                "Alpine Edge - Rolling"
            )
            ;;
    esac
    
    echo ""
    echo -e "${WHITE}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║${NC}              ${BOLD}Select ${SELECTED_DISTRO^} Version${NC}                            ${WHITE}║${NC}"
    echo -e "${WHITE}╠══════════════════════════════════════════════════════════════════╣${NC}"
    
    local i=0
    for key in "${version_keys[@]}"; do
        printf "${WHITE}║${NC}  ${GREEN}%d)${NC} %-65s ${WHITE}║${NC}\n" "$((i+1))" "${version_names[$i]}"
        ((i++))
    done
    
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    local max_choice=${#version_keys[@]}
    while true; do
        if [[ -t 0 ]]; then
            read -rp "Enter your choice [1-${max_choice}]: " choice
        else
            read -rp "Enter your choice [1-${max_choice}]: " choice < /dev/tty
        fi
        choice=$(echo "$choice" | tr -d '[:space:]')
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "$max_choice" ]]; then
            SELECTED_VERSION="${version_keys[$((choice-1))]}"
            break
        else
            print_error "Invalid selection. Please enter a number between 1 and ${max_choice}."
        fi
    done
    
    print_success "Selected version: ${SELECTED_VERSION}"
}

select_disk() {
    print_step "Select installation disk..."
    
    local disk_names=()
    local disk_descs=()
    
    # Get the disk where root is mounted
    local root_disk=""
    root_disk=$(lsblk -no PKNAME "$(findmnt -n -o SOURCE /)" 2>/dev/null | head -1)
    
    while IFS= read -r line; do
        local name size type model
        name=$(echo "$line" | awk '{print $1}')
        size=$(echo "$line" | awk '{print $2}')
        type=$(echo "$line" | awk '{print $3}')
        model=$(lsblk -dno MODEL "/dev/$name" 2>/dev/null | xargs)
        [[ -z "$model" ]] && model="Unknown"
        disk_names+=("$name")
        
        # Check if this is the boot disk
        if [[ "$name" == "$root_disk" ]]; then
            disk_descs+=("/dev/$name - ${size} (${model}) [BOOT DISK - NOT RECOMMENDED]")
        else
            disk_descs+=("/dev/$name - ${size} (${model})")
        fi
    done < <(lsblk -dno NAME,SIZE,TYPE | grep disk)
    
    if [[ ${#disk_names[@]} -eq 0 ]]; then
        die "No disks found"
    fi
    
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║${NC}  ${BOLD}⚠ WARNING: ALL DATA ON SELECTED DISK WILL BE ERASED!${NC}           ${RED}║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${WHITE}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║${NC}              ${BOLD}Select Installation Disk${NC}                           ${WHITE}║${NC}"
    echo -e "${WHITE}╠══════════════════════════════════════════════════════════════════╣${NC}"
    
    local i=0
    for name in "${disk_names[@]}"; do
        printf "${WHITE}║${NC}  ${GREEN}%d)${NC} %-65s ${WHITE}║${NC}\n" "$((i+1))" "${disk_descs[$i]}"
        ((i++))
    done
    
    echo -e "${WHITE}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    local max_choice=${#disk_names[@]}
    while true; do
        if [[ -t 0 ]]; then
            read -rp "Enter your choice [1-${max_choice}]: " choice
        else
            read -rp "Enter your choice [1-${max_choice}]: " choice < /dev/tty
        fi
        choice=$(echo "$choice" | tr -d '[:space:]')
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "$max_choice" ]]; then
            INSTALL_DISK="/dev/${disk_names[$((choice-1))]}"
            
            # Warn if installing to boot disk
            if [[ "${disk_names[$((choice-1))]}" == "$root_disk" ]]; then
                echo ""
                echo -e "${RED}╔══════════════════════════════════════════════════════════════════╗${NC}"
                echo -e "${RED}║${NC}  ${BOLD}⚠ CRITICAL WARNING!${NC}                                            ${RED}║${NC}"
                echo -e "${RED}║${NC}  You selected the disk you're currently booted from!         ${RED}║${NC}"
                echo -e "${RED}║${NC}  This is ${BOLD}NOT${NC} recommended and may cause system crash.        ${RED}║${NC}"
                echo -e "${RED}║${NC}                                                            ${RED}║${NC}"
                echo -e "${RED}║${NC}  ${YELLOW}For testing, use a VM with a SECOND disk.${NC}                 ${RED}║${NC}"
                echo -e "${RED}║${NC}  ${YELLOW}For production, boot from a rescue/live USB first.${NC}         ${RED}║${NC}"
                echo -e "${RED}╚══════════════════════════════════════════════════════════════════╝${NC}"
                echo ""
                read -rp "Are you SURE you want to continue? Type 'YES' to proceed: " confirm
                if [[ "$confirm" != "YES" ]]; then
                    print_info "Selection cancelled. Please choose another disk."
                    continue
                fi
            fi
            break
        else
            print_error "Invalid selection. Please enter a number between 1 and ${max_choice}."
        fi
    done
    
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
    
    # Check if we need to download files from GitHub (when run via curl | bash)
    local github_raw="https://raw.githubusercontent.com/zarigata/remote-reinstall/main"
    
    # Download lib files if not present
    if [[ ! -f "${LIB_DIR}/common.sh" ]]; then
        print_info "Downloading library files from GitHub..."
        mkdir -p "$LIB_DIR"
        curl -fsSL "${github_raw}/lib/common.sh" -o "${LIB_DIR}/common.sh" || die "Failed to download common.sh"
        curl -fsSL "${github_raw}/lib/partition.sh" -o "${LIB_DIR}/partition.sh" || die "Failed to download partition.sh"
        curl -fsSL "${github_raw}/lib/network.sh" -o "${LIB_DIR}/network.sh" || die "Failed to download network.sh"
    fi
    
    # Source the distro-specific installer
    local installer_script="${DISTROS_DIR}/${SELECTED_DISTRO}.sh"
    
    # Download distro installer if not present
    if [[ ! -f "$installer_script" ]]; then
        print_info "Downloading ${SELECTED_DISTRO} installer from GitHub..."
        mkdir -p "$DISTROS_DIR"
        curl -fsSL "${github_raw}/distros/${SELECTED_DISTRO}.sh" -o "$installer_script" || die "Failed to download ${SELECTED_DISTRO}.sh"
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
