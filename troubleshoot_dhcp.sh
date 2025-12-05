#!/bin/bash

################################################################################
# DHCP Troubleshooting Script for Red Hat-based Systems
# 
# This script diagnoses common DHCP configuration issues on Red Hat Enterprise
# Linux, CentOS, Fedora, and similar distributions.
#
# Usage: sudo ./troubleshoot_dhcp.sh [interface]
#        If no interface is specified, all interfaces will be checked
################################################################################

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get the interface parameter if provided
TARGET_INTERFACE="$1"

# Validate interface name to prevent command injection
if [ -n "$TARGET_INTERFACE" ]; then
    # Interface names should only contain alphanumeric characters, hyphens, underscores, and dots
    if ! [[ "$TARGET_INTERFACE" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        echo -e "${RED}Error: Invalid interface name '${TARGET_INTERFACE}'${NC}"
        echo "Interface names should only contain alphanumeric characters, hyphens, underscores, and dots"
        exit 1
    fi
fi

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root${NC}" 
   echo "Please run with: sudo $0"
   exit 1
fi

echo "=========================================="
echo "DHCP Troubleshooting Script for Red Hat"
echo "=========================================="
echo ""

# Function to print section headers
print_header() {
    echo ""
    echo -e "${BLUE}==== $1 ====${NC}"
}

# Function to print success messages
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Function to print warning messages
print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Function to print error messages
print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# 1. Check Network Interfaces
print_header "Network Interfaces"

if [ -n "$TARGET_INTERFACE" ]; then
    echo "Checking interface: $TARGET_INTERFACE"
    INTERFACES="$TARGET_INTERFACE"
else
    echo "Detecting all network interfaces..."
    INTERFACES=$(ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$')
fi

for iface in $INTERFACES; do
    echo ""
    echo "Interface: $iface"
    
    # Check if interface exists
    if ! ip link show "$iface" &>/dev/null; then
        print_error "Interface $iface does not exist"
        continue
    fi
    
    # Check interface status
    STATE=$(ip link show "$iface" | awk '/state/ {print $9}')
    if [ "$STATE" = "UP" ]; then
        print_success "Interface $iface is UP"
    else
        print_warning "Interface $iface is $STATE"
    fi
    
    # Check IP configuration
    IP_ADDR=$(ip addr show "$iface" | grep 'inet ' | awk '{print $2}')
    if [ -n "$IP_ADDR" ]; then
        print_success "IP Address: $IP_ADDR"
    else
        print_warning "No IP address assigned to $iface"
    fi
done

# 2. Check DHCP Client Service
print_header "DHCP Client Services"

# Check for NetworkManager
if systemctl is-active --quiet NetworkManager; then
    print_success "NetworkManager is active"
    
    # Show NetworkManager connection status
    echo ""
    echo "NetworkManager connections:"
    nmcli connection show
    
    if [ -n "$TARGET_INTERFACE" ]; then
        echo ""
        echo "NetworkManager device status for $TARGET_INTERFACE:"
        nmcli device show "$TARGET_INTERFACE" 2>/dev/null || print_warning "Could not get device status"
    fi
else
    print_warning "NetworkManager is not active"
fi

# Check for dhclient process
DHCLIENT_PROCS=$(ps aux | grep -v grep | grep dhclient)
if [ -n "$DHCLIENT_PROCS" ]; then
    print_success "dhclient processes found:"
    echo "$DHCLIENT_PROCS"
else
    print_warning "No dhclient processes running"
fi

# 3. Check DHCP Lease Information
print_header "DHCP Lease Information"

# Check for dhclient leases
LEASE_FILES=""
if [ -d /var/lib/dhclient ]; then
    LEASE_FILES=$(find /var/lib/dhclient -name "*.lease*" 2>/dev/null)
fi
if [ -d /var/lib/NetworkManager ]; then
    NM_LEASES=$(find /var/lib/NetworkManager -name "*.lease*" 2>/dev/null)
    if [ -n "$NM_LEASES" ]; then
        LEASE_FILES="${LEASE_FILES}${LEASE_FILES:+$'\n'}${NM_LEASES}"
    fi
fi

if [ -n "$LEASE_FILES" ]; then
    echo "Found DHCP lease files:"
    while IFS= read -r lease; do
        if [ -z "$lease" ]; then
            continue
        fi
        echo ""
        echo "File: $lease"
        if [ -f "$lease" ] && [ -r "$lease" ]; then
            tail -20 "$lease"
        fi
    done <<< "$LEASE_FILES"
else
    print_warning "No DHCP lease files found"
fi

# 4. Check Network Configuration Files
print_header "Network Configuration Files"

# Check NetworkManager configuration
if [ -d /etc/NetworkManager/system-connections ]; then
    echo "NetworkManager system connections:"
    ls -la /etc/NetworkManager/system-connections/
fi

# Check traditional network scripts
if [ -d /etc/sysconfig/network-scripts ]; then
    echo ""
    echo "Network scripts in /etc/sysconfig/network-scripts/:"
    
    if [ -n "$TARGET_INTERFACE" ]; then
        CONFIG_FILE="/etc/sysconfig/network-scripts/ifcfg-$TARGET_INTERFACE"
        if [ -f "$CONFIG_FILE" ]; then
            echo ""
            echo "Configuration for $TARGET_INTERFACE:"
            cat "$CONFIG_FILE"
            
            # Check if BOOTPROTO is set to dhcp
            if grep -q "BOOTPROTO=dhcp" "$CONFIG_FILE" 2>/dev/null; then
                print_success "Interface configured for DHCP"
            elif grep -q "BOOTPROTO=none" "$CONFIG_FILE" 2>/dev/null || grep -q "BOOTPROTO=static" "$CONFIG_FILE" 2>/dev/null; then
                print_warning "Interface configured for static IP, not DHCP"
            fi
        else
            print_warning "No configuration file found for $TARGET_INTERFACE"
        fi
    else
        ls -la /etc/sysconfig/network-scripts/ifcfg-* 2>/dev/null || print_warning "No interface configuration files found"
    fi
fi

# 5. Check Firewall Status
print_header "Firewall Configuration"

if command -v firewall-cmd &>/dev/null; then
    if systemctl is-active --quiet firewalld; then
        print_success "firewalld is active"
        
        echo ""
        echo "Firewall zones:"
        firewall-cmd --get-active-zones
        
        echo ""
        echo "DHCP service status in firewall:"
        # Get zones from first word of each non-indented line
        for zone in $(firewall-cmd --get-active-zones | awk '/^[^ ]/ {print $1}'); do
            if firewall-cmd --zone="$zone" --list-services 2>/dev/null | grep -q dhcp; then
                print_success "DHCP allowed in zone: $zone"
            else
                print_warning "DHCP not explicitly allowed in zone: $zone"
            fi
        done
    else
        print_warning "firewalld is not active"
    fi
else
    print_warning "firewalld not installed"
fi

# Check iptables if firewalld is not running
if ! systemctl is-active --quiet firewalld; then
    if command -v iptables &>/dev/null; then
        echo ""
        echo "iptables rules:"
        iptables -L -n | grep -E "DHCP|67|68" || echo "No specific DHCP rules found"
    fi
fi

# 6. Check SELinux Status
print_header "SELinux Status"

if command -v getenforce &>/dev/null; then
    SELINUX_STATUS=$(getenforce)
    echo "SELinux status: $SELINUX_STATUS"
    
    if [ "$SELINUX_STATUS" = "Enforcing" ]; then
        print_warning "SELinux is in enforcing mode - check for denials"
        
        # Check for recent SELinux denials related to DHCP
        if command -v ausearch &>/dev/null; then
            echo ""
            echo "Recent SELinux denials (last 24 hours):"
            ausearch -m avc -ts recent 2>/dev/null | grep -i dhcp || echo "No DHCP-related denials found"
        fi
    elif [ "$SELINUX_STATUS" = "Permissive" ]; then
        print_warning "SELinux is in permissive mode"
    else
        print_success "SELinux is disabled"
    fi
else
    print_warning "SELinux tools not found"
fi

# 7. Check System Logs
print_header "Recent DHCP-Related Log Entries"

echo "Checking journal logs for DHCP activity (last 50 entries):"
journalctl -n 50 --no-pager | grep -iE "dhcp|NetworkManager" || print_warning "No recent DHCP log entries found"

echo ""
echo "Checking /var/log/messages for DHCP activity (last 20 entries):"
if [ -f /var/log/messages ]; then
    grep -iE "dhcp" /var/log/messages | tail -20 || print_warning "No DHCP entries in /var/log/messages"
else
    print_warning "/var/log/messages not found"
fi

# 8. Network Connectivity Tests
print_header "Network Connectivity Tests"

for iface in $INTERFACES; do
    # Skip loopback
    if [ "$iface" = "lo" ]; then
        continue
    fi
    
    echo ""
    echo "Testing interface: $iface"
    
    # Get default gateway
    GATEWAY=$(ip route show dev "$iface" | grep default | awk '{print $3}')
    if [ -n "$GATEWAY" ]; then
        print_success "Default gateway: $GATEWAY"
        
        # Ping gateway
        echo "Pinging gateway..."
        if ping -c 2 -W 2 "$GATEWAY" &>/dev/null; then
            print_success "Gateway is reachable"
        else
            print_error "Cannot reach gateway"
        fi
    else
        print_warning "No default gateway configured for $iface"
    fi
    
    # Check DNS
    DNS_SERVERS=$(nmcli -g IP4.DNS device show "$iface" 2>/dev/null)
    if [ -n "$DNS_SERVERS" ]; then
        print_success "DNS servers: $DNS_SERVERS"
    else
        print_warning "No DNS servers configured for $iface"
    fi
done

# 9. Recommendations
print_header "Troubleshooting Recommendations"

echo ""
echo "Common solutions to try:"
echo "1. Restart NetworkManager:"
echo "   sudo systemctl restart NetworkManager"
echo ""
echo "2. Release and renew DHCP lease:"
echo "   sudo nmcli connection down <connection-name>"
echo "   sudo nmcli connection up <connection-name>"
echo "   Or: sudo dhclient -r <interface> && sudo dhclient <interface>"
echo ""
echo "3. Check physical connection:"
echo "   sudo ethtool <interface> | grep 'Link detected'"
echo ""
echo "4. Verify DHCP server is reachable:"
echo "   sudo nmap -sU -p 67 <dhcp-server-ip>"
echo ""
echo "5. Check for NetworkManager conflicts:"
echo "   sudo systemctl stop NetworkManager"
echo "   sudo dhclient -v <interface>"
echo ""
echo "6. Review full system logs:"
echo "   sudo journalctl -u NetworkManager -f"
echo "   sudo journalctl -xe"
echo ""
echo "7. Test DHCP discovery manually:"
echo "   sudo dhclient -v -d <interface>"
echo ""

print_header "Script Complete"
echo ""
echo "If issues persist, review the output above for errors and warnings."
echo "Check that:"
echo "  - Interface is physically connected"
echo "  - DHCP server is operational"
echo "  - Network configuration is set to use DHCP"
echo "  - Firewall allows DHCP traffic (UDP ports 67-68)"
echo "  - No conflicting network management tools are running"
echo ""
