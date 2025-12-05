# dhcp_troubleshoot

## DHCP Troubleshooting Script for Red Hat

This repository contains a comprehensive DHCP troubleshooting script designed for Red Hat-based Linux distributions (RHEL, CentOS, Fedora, etc.).

### Features

The `troubleshoot_dhcp.sh` script helps diagnose common DHCP configuration issues by checking:

- Network interface status and configuration
- DHCP client services (NetworkManager, dhclient)
- DHCP lease information
- Network configuration files
- Firewall settings (firewalld, iptables)
- SELinux status and denials
- System logs for DHCP-related entries
- Network connectivity (gateway, DNS)

### Usage

Run the script with root privileges:

```bash
sudo ./troubleshoot_dhcp.sh
```

To check a specific network interface:

```bash
sudo ./troubleshoot_dhcp.sh eth0
```

### Requirements

- Red Hat-based Linux distribution (RHEL, CentOS, Fedora, Rocky Linux, AlmaLinux)
- Root or sudo privileges
- Common network utilities (ip, nmcli, systemctl)

### Output

The script provides color-coded output:
- ✓ Green: Success/Normal status
- ⚠ Yellow: Warnings that may need attention
- ✗ Red: Errors that need to be fixed

### Troubleshooting Tips

The script provides recommendations at the end, including:
- Restarting NetworkManager
- Releasing and renewing DHCP leases
- Checking physical connections
- Verifying DHCP server reachability
- Reviewing system logs

### Example

```bash
$ sudo ./troubleshoot_dhcp.sh ens33
==========================================
DHCP Troubleshooting Script for Red Hat
==========================================

==== Network Interfaces ====
Checking interface: ens33

Interface: ens33
✓ Interface ens33 is UP
✓ IP Address: 192.168.1.100/24

==== DHCP Client Services ====
✓ NetworkManager is active
...
```

### License

This is free and unencumbered software released into the public domain.