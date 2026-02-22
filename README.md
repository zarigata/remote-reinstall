# 🔄 Remote Linux Reinstaller

**Transform any Linux machine into a fresh distribution - completely remotely via SSH!**

```
curl -fsSL https://raw.githubusercontent.com/zarigata/remote-reinstall/main/install.sh | sudo bash
```

## ⚡ What is this?

Remote Linux Reinstaller is a powerful tool that allows you to completely reinstall a Linux machine over SSH without any physical access. It works like DietPi's "Make your own distribution" feature but supports multiple distributions.

### 🎯 Key Features

- 🖥️ **Beautiful TUI** - Interactive menu to select distribution and configure options
- 🔐 **SSH Preservation** - Never lose access to your machine during reinstall
- 🌐 **Network Config** - Automatically preserves IP address and network settings
- 📦 **7 Distributions** - Ubuntu, Debian, Proxmox, Fedora, Rocky Linux, Arch, Alpine
- 🔑 **SSH Key Support** - Pre-configures SSH keys for passwordless access
- 🚀 **Fully Automated** - One command to completely transform your server

---

## 📋 Supported Distributions

| Distribution | Versions | Best For |
|-------------|----------|----------|
| **Ubuntu** | 24.04, 22.04, 20.04 | General purpose, beginners, cloud |
| **Debian** | 12, 11 | Stability, servers, minimal |
| **Proxmox VE** | 8, 7 | Virtualization, homelab, Proxmox clusters |
| **Fedora** | 40, 39 | Latest features, development |
| **Rocky Linux** | 9, 8 | Enterprise, RHEL-compatible |
| **Arch Linux** | Rolling | Advanced users, custom setups |
| **Alpine Linux** | 3.19, 3.18, edge | Containers, security, minimal footprint |

---

## 🚀 Quick Start

### Interactive Mode (Recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/zarigata/remote-reinstall/main/install.sh | sudo bash
```

This will launch an interactive TUI where you can:
1. Select your target distribution
2. Choose the version
3. Select the installation disk
4. Configure hostname, username, password
5. Add SSH keys
6. Confirm and install

### Non-Interactive Mode (Automation)

```bash
curl -fsSL https://raw.githubusercontent.com/zarigata/remote-reinstall/main/install.sh | \
  sudo bash -s -- \
    --distro ubuntu \
    --version 24.04 \
    --disk /dev/sda \
    --hostname myserver \
    --username admin \
    --password "your-secure-password" \
    --ssh-port 22 \
    --ssh-key "ssh-rsa AAAA...your-public-key"
```

---

## ⚙️ Command Line Options

| Option | Description | Example |
|--------|-------------|---------|
| `-d, --distro` | Distribution to install | `ubuntu`, `debian`, `proxmox` |
| `-v, --version` | Version to install | `24.04`, `12`, `8` |
| `--disk` | Target disk device | `/dev/sda` |
| `--hostname` | System hostname | `myserver` |
| `--username` | Primary user name | `admin` |
| `--password` | User password | `SecurePass123!` |
| `--ssh-port` | SSH port (default: 22) | `2222` |
| `--ssh-key` | SSH public key | `"ssh-rsa AAAA..."` |
| `--force` | Skip confirmation | - |
| `--verbose` | Enable verbose output | - |
| `-h, --help` | Show help message | - |

---

## 🖼️ Screenshots

### Main Menu
```
╔══════════════════════════════════════════════════════════════════╗
║          Select Distribution                                     ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                  ║
║   ┌─────────────────────────────────────────────────────────┐   ║
║   │     Ubuntu LTS         (User-friendly, great support)   │   ║
║   │ [*] Debian Stable      (Rock-solid stability)           │   ║
║   │     Proxmox VE         (Virtualization platform)         │   ║
║   │     Fedora Server      (Cutting-edge features)           │   ║
║   │     Rocky Linux        (RHEL-compatible, enterprise)     │   ║
║   │     Arch Linux         (Rolling release, DIY)            │   ║
║   │     Alpine Linux       (Lightweight, security-focused)   │   ║
║   └─────────────────────────────────────────────────────────┘   ║
║                                                                  ║
║               <OK>                    <Cancel>                   ║
╚══════════════════════════════════════════════════════════════════╝
```

### Installation Summary
```
╔══════════════════════════════════════════════════════════════════╗
║                    INSTALLATION SUMMARY                          ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                  ║
║  Distribution:    Ubuntu 24.04                                   ║
║  Target Disk:     /dev/sda                                       ║
║  Hostname:        myserver                                       ║
║  Username:        admin                                          ║
║  SSH Port:        22                                             ║
║  SSH Key:         Yes                                            ║
║  Boot Mode:       UEFI                                           ║
║                                                                  ║
╠══════════════════════════════════════════════════════════════════╣
║  ⚠ WARNING: This will PERMANENTLY DELETE ALL DATA               ║
║             on /dev/sda                                          ║
║                                                                  ║
║  Current IP: 192.168.1.100 (will be preserved)                  ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
```

---

## 🔧 How It Works

1. **Detects System** - Identifies current OS, architecture, boot mode (UEFI/BIOS), and network configuration
2. **Partitions Disk** - Creates appropriate partition layout for selected distribution
3. **Bootstrap System** - Uses distribution-specific tools to install base system:
   - Ubuntu/Debian: `debootstrap`
   - Fedora/Rocky: `dnf --installroot`
   - Arch: `pacstrap`
   - Alpine: `apk --root`
4. **Configures System** - Sets up hostname, users, SSH, networking
5. **Installs Bootloader** - Configures GRUB for UEFI or BIOS boot
6. **Reboots** - System boots into fresh installation with preserved network access

---

## ⚠️ Important Warnings

**This tool will COMPLETELY ERASE the selected disk!**

- All data will be lost
- The entire operating system will be replaced
- Only use on machines you intend to completely reinstall
- Always have a backup of important data

**Requirements:**
- Must be run as root
- Machine must have internet access
- At least 2GB RAM recommended
- Target disk must have at least 10GB space

---

## 🛡️ Security Features

- Passwords are never logged
- SSH keys configured during installation
- Root login disabled via SSH
- Configurable SSH port
- Firewall enabled by default (where applicable)

---

## 📁 Project Structure

```
remote-reinstall/
├── install.sh          # Main entry point
├── lib/
│   ├── common.sh       # Shared utilities (chroot, users, fstab)
│   ├── network.sh      # Network configuration preservation
│   └── partition.sh    # Disk partitioning functions
├── distros/
│   ├── ubuntu.sh       # Ubuntu installer (debootstrap)
│   ├── debian.sh       # Debian installer (debootstrap)
│   ├── proxmox.sh      # Proxmox VE installer
│   ├── fedora.sh       # Fedora installer (dnf)
│   ├── rocky.sh        # Rocky Linux installer (dnf)
│   ├── arch.sh         # Arch Linux installer (pacstrap)
│   └── alpine.sh       # Alpine Linux installer (apk)
├── configs/            # Configuration templates
└── README.md
```

---

## 🤝 Contributing

Contributions are welcome! Here's how to help:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Adding a New Distribution

1. Create `distros/your-distro.sh` with an `install_your_distro()` function
2. Add the distro to the selection menu in `install.sh`
3. Update this README with the new distribution
4. Test thoroughly before submitting PR

---

## 📜 License

MIT License - See [LICENSE](LICENSE) for details.

---

## 🙏 Acknowledgments

- Inspired by [DietPi](https://dietpi.com/) and their "Make your own distribution" feature
- Built with love for the homelab and sysadmin community
- Thanks to all contributors

---

## 🐛 Bug Reports

Found a bug? Please open an issue with:
- Current distribution and version
- Target distribution and version
- Full log output (from `/tmp/remote-reinstall-*.log`)
- Hardware details

---

<p align="center">
  <strong>Made with ❤️ for remote server management</strong>
</p>
