#!/bin/bash

save_network_config() {
    local target="$1"
    
    print_step "Saving network configuration..."
    
    local interface="$PRIMARY_INTERFACE"
    local ip_addr="$PRIMARY_IP"
    local gateway=$(ip route | grep default | awk '{print $3}' | head -1)
    local dns_servers=$(grep "nameserver" /etc/resolv.conf | awk '{print $2}' | tr '\n' ' ')
    local netmask=$(ip -4 addr show "$interface" | grep inet | awk '{print $2}' | cut -d/ -f2)
    local prefix=$(ip -4 addr show "$interface" | grep inet | awk '{print $2}' | cut -d/ -f2)
    
    print_info "Interface: ${interface}"
    print_info "IP: ${ip_addr}/${prefix}"
    print_info "Gateway: ${gateway}"
    print_info "DNS: ${dns_servers}"
    
    cat > "${target}/tmp/network-config.bak" << EOF
INTERFACE=${interface}
IP_ADDR=${ip_addr}
GATEWAY=${gateway}
DNS_SERVERS="${dns_servers}"
PREFIX=${prefix}
EOF
    
    print_success "Network configuration saved"
}

configure_network_systemd() {
    local target="$1"
    local interface="$2"
    
    print_step "Configuring systemd-networkd..."
    
    local gateway=$(ip route | grep default | awk '{print $3}' | head -1)
    local dns_servers=$(grep "nameserver" /etc/resolv.conf | awk '{print $2}' | tr '\n' ' ')
    local prefix=$(ip -4 addr show "$interface" | grep inet | awk '{print $2}' | cut -d/ -f2)
    
    mkdir -p "${target}/etc/systemd/network"
    
    cat > "${target}/etc/systemd/network/20-wired.network" << EOF
[Match]
Name=${interface}

[Network]
Address=${PRIMARY_IP}/${prefix}
Gateway=${gateway}
DNS=${dns_servers}
EOF
    
    print_success "systemd-networkd configured"
}

configure_network_interfaces() {
    local target="$1"
    local interface="$2"
    
    print_step "Configuring /etc/network/interfaces..."
    
    local gateway=$(ip route | grep default | awk '{print $3}' | head -1)
    local dns_servers=$(grep "nameserver" /etc/resolv.conf | awk '{print $2}' | tr '\n' ' ')
    local prefix=$(ip -4 addr show "$interface" | grep inet | awk '{print $2}' | cut -d/ -f2)
    
    cat > "${target}/etc/network/interfaces" << EOF
auto lo
iface lo inet loopback

auto ${interface}
iface ${interface} inet static
    address ${PRIMARY_IP}
    netmask $((2**32 - 2**(32-prefix)))
    gateway ${gateway}
    dns-nameservers ${dns_servers}
EOF
    
    print_success "/etc/network/interfaces configured"
}

configure_network_nm() {
    local target="$1"
    local interface="$2"
    
    print_step "Configuring NetworkManager..."
    
    local gateway=$(ip route | grep default | awk '{print $3}' | head -1)
    local dns_servers=$(grep "nameserver" /etc/resolv.conf | awk '{print $2}' | tr ';' ' ')
    local prefix=$(ip -4 addr show "$interface" | grep inet | awk '{print $2}' | cut -d/ -f2)
    
    mkdir -p "${target}/etc/NetworkManager/system-connections"
    
    cat > "${target}/etc/NetworkManager/system-connections/${interface}.nmconnection" << EOF
[connection]
id=${interface}
type=ethernet
interface-name=${interface}

[ipv4]
method=manual
addresses=${PRIMARY_IP}/${prefix}
gateway=${gateway}
dns=${dns_servers}
EOF
    
    chmod 600 "${target}/etc/NetworkManager/system-connections/${interface}.nmconnection"
    
    print_success "NetworkManager configured"
}
