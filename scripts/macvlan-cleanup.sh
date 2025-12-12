#!/usr/bin/env bash
set -euo pipefail

echo "=== Macvlan Cleanup Script ==="
echo "This will remove macvlan network interface bindings."
echo

# Check if macvlan0 exists
if ! ip link show macvlan0 >/dev/null 2>&1; then
    echo "No macvlan0 interface found - nothing to clean up."
    echo "(This is normal if HOST_SHIM_IP was not configured)"
    exit 0
fi

# Confirm cleanup action
read -p "Are you sure you want to clean up macvlan0? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo "Starting cleanup..."
echo "Note: Stop Docker containers manually before running this script."
echo

# Remove host macvlan interface
echo "→ Removing host macvlan interface..."
if ip link show macvlan0 >/dev/null 2>&1; then
    # Bring interface down
    sudo ip link set macvlan0 down 2>/dev/null || true
    echo "  ✓ macvlan0 interface brought down"

    # Remove interface
    sudo ip link delete macvlan0 2>/dev/null || true
    echo "  ✓ macvlan0 interface deleted"
else
    echo "  • macvlan0 interface not found"
fi

# Verify cleanup
echo
echo "=== Cleanup Verification ==="

# Check if macvlan0 still exists
if ip link show macvlan0 >/dev/null 2>&1; then
    echo "⚠️  WARNING: macvlan0 interface still exists"
    ip -o addr show dev macvlan0
else
    echo "✓ macvlan0 interface successfully removed"
fi

# Check for any remaining macvlan interfaces
MACVLAN_INTERFACES=$(ip link show type macvlan 2>/dev/null | grep -E "^[0-9]+:" | wc -l || echo "0")
if [ "$MACVLAN_INTERFACES" -gt 0 ]; then
    echo "⚠️  WARNING: Found $MACVLAN_INTERFACES other macvlan interfaces:"
    ip link show type macvlan 2>/dev/null | grep -E "^[0-9]+:" | awk '{print "   " $2}' || true
else
    echo "✓ No macvlan interfaces found"
fi

echo
echo "=== Cleanup Complete ==="
