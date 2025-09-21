#!/usr/bin/env bash
set -euo pipefail

# Detect script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Auto-detect network interface from default route
DETECTED_IF=$(ip route show default 2>/dev/null | awk '/^default/ {print $5; exit}')

# Default values
PARENT_IF="${DETECTED_IF:-eth0}"  # Use detected interface or fallback to eth0
MAC_PREFIX="8C:1F:64:A2"
CAM_COUNT=2
WRITE_TO_FILE=false
QUICK_SCAN=true  # Quick scan is now the default

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Generate network configuration for ONVIF devices

OPTIONS:
    -i INTERFACE    Parent network interface (default: auto-detected or eth0)
    -m MAC_PREFIX   MAC address prefix (default: 8C:1F:64:A2)
    -c COUNT        Number of cameras (default: 2)
    -w              Write configuration to .env file
    -f              Full network scan (default is quick targeted scan)
    -h              Show this help message

EXAMPLES:
    $0                          # Auto-detect interface, quick scan, display suggestions
    $0 -f                       # Full network scan (slower but more thorough)
    $0 -i wlan0 -c 3           # Use WiFi interface, 3 cameras
    $0 -w                      # Write to .env file automatically
    $0 -m 02:42:AC:11 -w       # Custom MAC prefix and write to file

PREREQUISITES:
    - arp-scan must be installed
    - Run with sudo for network scanning capabilities
EOF
}

# Parse command line arguments
while getopts "i:m:c:wfh" opt; do
    case $opt in
        i) PARENT_IF="$OPTARG" ;;
        m) MAC_PREFIX="$OPTARG" ;;
        c) CAM_COUNT="$OPTARG" ;;
        w) WRITE_TO_FILE=true ;;
        f) QUICK_SCAN=false ;;  # Full scan mode
        h) show_help; exit 0 ;;
        *) echo "Invalid option. Use -h for help."; exit 1 ;;
    esac
done

echo -e "${BLUE}=== Network Configuration Generator ===${NC}"
echo

# Check if arp-scan is installed
if ! command -v arp-scan >/dev/null 2>&1; then
    echo -e "${RED}Error: arp-scan is not installed${NC}"
    echo "Please install it first:"
    echo "  Ubuntu/Debian: sudo apt-get install arp-scan"
    echo "  macOS: brew install arp-scan"
    echo "  RHEL/CentOS: sudo yum install arp-scan"
    exit 1
fi

# Check if interface exists
if ! ip link show "$PARENT_IF" >/dev/null 2>&1; then
    echo -e "${RED}Error: Interface '$PARENT_IF' not found${NC}"
    echo "Available interfaces:"
    ip link show | grep -E "^[0-9]+:" | awk '{print "  " $2}' | sed 's/:$//'
    exit 1
fi

# Get network information
echo -e "${YELLOW}Detecting network configuration...${NC}"

# Get IP and subnet from interface
IP_INFO=$(ip addr show "$PARENT_IF" | grep "inet " | head -1 | awk '{print $2}')
if [ -z "$IP_INFO" ]; then
    echo -e "${RED}Error: No IP address found on interface '$PARENT_IF'${NC}"
    exit 1
fi

HOST_IP=$(echo "$IP_INFO" | cut -d'/' -f1)
CIDR=$(echo "$IP_INFO" | cut -d'/' -f2)

# Calculate subnet
IFS='.' read -r i1 i2 i3 i4 <<< "$HOST_IP"
case $CIDR in
    24) SUBNET="$i1.$i2.$i3.0/24" ;;
    16) SUBNET="$i1.$i2.0.0/16" ;;
    8)  SUBNET="$i1.0.0.0/8" ;;
    *)  echo -e "${RED}Warning: Unusual CIDR /$CIDR, assuming /24${NC}"; SUBNET="$i1.$i2.$i3.0/24" ;;
esac

# Get default gateway
GATEWAY=$(ip route show default dev "$PARENT_IF" | awk '{print $3}' | head -1)
if [ -z "$GATEWAY" ]; then
    GATEWAY="$i1.$i2.$i3.1"
    echo -e "${YELLOW}Warning: Could not detect gateway, assuming $GATEWAY${NC}"
fi

echo -e "${GREEN}Network Details:${NC}"
if [ -n "$DETECTED_IF" ] && [ "$PARENT_IF" = "$DETECTED_IF" ]; then
    echo "  Interface: $PARENT_IF (auto-detected)"
else
    echo "  Interface: $PARENT_IF"
fi
echo "  Host IP: $HOST_IP"
echo "  Subnet: $SUBNET"
echo "  Gateway: $GATEWAY"
echo

# Scan for used IPs
echo -e "${YELLOW}Scanning network for used IP addresses...${NC}"
SCAN_NETWORK=$(echo "$SUBNET" | cut -d'/' -f1 | sed 's/\.0$//')

# Determine scan ranges based on requirements
# We need IPs in ranges: 240-250 for shim, 200-230 for cameras
if [ "$QUICK_SCAN" = true ]; then
    # Default: quick targeted scan
    SCAN_RANGES="200-230 240-250"
else
    echo -e "${BLUE}Using full network scan (this may take longer)${NC}"
    SCAN_RANGES="1-254"
fi

# Perform ARP scan
if [ "$EUID" -eq 0 ]; then
    if [ "$QUICK_SCAN" = true ]; then
        # Targeted scan with timeout for faster results
        USED_IPS=""
        for range in $SCAN_RANGES; do
            START=$(echo $range | cut -d'-' -f1)
            END=$(echo $range | cut -d'-' -f2)
            # Use arp-scan with specific IP range and short timeout
            RANGE_IPS=$(arp-scan --interface="$PARENT_IF" -t 100 "$i1.$i2.$i3.$START-$i1.$i2.$i3.$END" 2>/dev/null | grep -E "^[0-9]+\." | awk '{print $1}')
            if [ -n "$RANGE_IPS" ]; then
                USED_IPS="$USED_IPS$RANGE_IPS"$'\n'
            fi
        done
        USED_IPS=$(echo "$USED_IPS" | grep -v '^$' | sort -V | uniq)
    else
        # Full network scan with timeout
        USED_IPS=$(arp-scan --interface="$PARENT_IF" -t 500 -l 2>/dev/null | grep -E "^[0-9]+\." | awk '{print $1}' | sort -V)
    fi
else
    echo -e "${YELLOW}Note: Running without sudo, using basic ping scan (less reliable)${NC}"
    USED_IPS=""
    if [ "$QUICK_SCAN" = true ]; then
        # Quick scan - only check needed ranges
        for range in $SCAN_RANGES; do
            START=$(echo $range | cut -d'-' -f1)
            END=$(echo $range | cut -d'-' -f2)
            for i in $(seq $START $END); do
                if ping -c 1 -W 1 "$i1.$i2.$i3.$i" >/dev/null 2>&1; then
                    USED_IPS="$USED_IPS$i1.$i2.$i3.$i"$'\n'
                fi
            done
        done
    else
        # Full scan
        for i in {1..254}; do
            if ping -c 1 -W 1 "$i1.$i2.$i3.$i" >/dev/null 2>&1; then
                USED_IPS="$USED_IPS$i1.$i2.$i3.$i"$'\n'
            fi
        done
    fi
    USED_IPS=$(echo "$USED_IPS" | grep -v '^$' | sort -V)
fi

echo -e "${GREEN}Used IP addresses:${NC}"
if [ -n "$USED_IPS" ]; then
    echo "$USED_IPS" | while read -r ip; do
        echo "  $ip"
    done
else
    echo "  No active devices found"
fi
echo

# Find available IPs
echo -e "${YELLOW}Finding available IP addresses...${NC}"

# Function to check if IP is used
is_ip_used() {
    echo "$USED_IPS" | grep -q "^$1$"
}

# Suggest HOST_SHIM_IP (try high range first)
HOST_SHIM_IP=""
for i in {250..240}; do
    CANDIDATE="$i1.$i2.$i3.$i"
    if ! is_ip_used "$CANDIDATE"; then
        HOST_SHIM_IP="$CANDIDATE/24"
        break
    fi
done

if [ -z "$HOST_SHIM_IP" ]; then
    echo -e "${RED}Error: Could not find available IP for HOST_SHIM_IP${NC}"
    exit 1
fi

# Find consecutive IPs for cameras
CAM_IPS=()
BASE_IP=230

while [ ${#CAM_IPS[@]} -lt "$CAM_COUNT" ] && [ $BASE_IP -gt 200 ]; do
    CANDIDATE="$i1.$i2.$i3.$BASE_IP"
    if ! is_ip_used "$CANDIDATE"; then
        CAM_IPS+=("$CANDIDATE")
    fi
    ((BASE_IP--))
done

if [ ${#CAM_IPS[@]} -lt "$CAM_COUNT" ]; then
    echo -e "${RED}Error: Could not find $CAM_COUNT available consecutive IPs${NC}"
    exit 1
fi

# Generate MAC addresses
generate_mac() {
    local index=$1
    printf "%s:%02X:%02X" "$MAC_PREFIX" "$((index))" "$((index))"
}

echo -e "${GREEN}=== Suggested Configuration ===${NC}"
echo

# Generate configuration
CONFIG="# Ethernet NIC for macvlan
PARENT_IF=$PARENT_IF

# Your LAN
LAN_SUBNET=$SUBNET
LAN_GATEWAY=$GATEWAY

# Host-side macvlan shim (unused IP you confirmed free)
HOST_SHIM_IP=$HOST_SHIM_IP

# Virtual ONVIF devices (unique IPs + MACs)"

for i in $(seq 1 "$CAM_COUNT"); do
    CAM_IP=${CAM_IPS[$((i-1))]}
    CAM_MAC=$(generate_mac "$i")
    CONFIG="$CONFIG
CAM${i}_IP=$CAM_IP
CAM${i}_MAC=$CAM_MAC"
done

echo "$CONFIG"
echo

# Check if .env already exists
if [ -f "$PROJECT_ROOT/.env" ]; then
    echo -e "${YELLOW}Warning: .env file already exists${NC}"
    if [ "$WRITE_TO_FILE" = true ]; then
        echo -e "${YELLOW}Backing up existing .env to .env.backup${NC}"
        cp "$PROJECT_ROOT/.env" "$PROJECT_ROOT/.env.backup"
    fi
fi

# Write to file or ask user
if [ "$WRITE_TO_FILE" = true ]; then
    echo "$CONFIG" > "$PROJECT_ROOT/.env"
    # Fix ownership if running as root
    if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
        chown "$SUDO_USER:$SUDO_USER" "$PROJECT_ROOT/.env"
    fi
    echo -e "${GREEN}Configuration written to .env file${NC}"
else
    echo -e "${BLUE}Save this configuration to .env file? (y/N):${NC} "
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        if [ -f "$PROJECT_ROOT/.env" ]; then
            echo -e "${YELLOW}Backing up existing .env to .env.backup${NC}"
            cp "$PROJECT_ROOT/.env" "$PROJECT_ROOT/.env.backup"
        fi
        echo "$CONFIG" > "$PROJECT_ROOT/.env"
        # Fix ownership if running as root
        if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
            chown "$SUDO_USER:$SUDO_USER" "$PROJECT_ROOT/.env"
        fi
        echo -e "${GREEN}Configuration saved to .env file${NC}"
    else
        echo -e "${BLUE}Configuration not saved. Copy the above to .env manually.${NC}"
    fi
fi

echo
echo -e "${RED}⚠️  IMPORTANT: Update ONVIF Camera Configuration Files${NC}"
echo -e "${YELLOW}Before starting the containers, you MUST update the MAC addresses in:${NC}"
for i in $(seq 1 "$CAM_COUNT"); do
    CAM_MAC=$(generate_mac "$i")
    echo -e "  ${BLUE}onvif-cam${i}-macvlan.yaml${NC} → Update 'mac:' field to: ${GREEN}${CAM_MAC}${NC}"
done
echo -e "${YELLOW}Failure to update these will cause network conflicts!${NC}"
echo
echo -e "${GREEN}Next steps:${NC}"
echo "1. Review the .env file and adjust if needed"
echo "2. Update MAC addresses in onvif-cam*-macvlan.yaml files (see warning above)"
echo "3. Run: ./scripts/macvlan-setup.sh"
echo "4. Run: docker compose -f docker-compose.macvlan.yml up -d"