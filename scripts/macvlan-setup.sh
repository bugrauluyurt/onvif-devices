#!/usr/bin/env bash
set -euo pipefail
[ -f ../.env ] && source ../.env

# fallback autodetect if not set
if [ -z "${PARENT_IF:-}" ]; then
  PARENT_IF="$(ip route show default | awk '{print $5}' | head -n1)"
fi

if ! ip link show "$PARENT_IF" >/dev/null 2>&1; then
  echo "Parent interface '$PARENT_IF' not found. Set PARENT_IF in .env (e.g., eth0)." >&2
  exit 1
fi

echo "Using parent interface: $PARENT_IF"
echo "Creating macvlan0 shim at: ${HOST_SHIM_IP}"

sudo ip link add macvlan0 link "$PARENT_IF" type macvlan mode bridge 2>/dev/null || true
sudo ip addr add "$HOST_SHIM_IP" dev macvlan0 2>/dev/null || true
sudo ip link set macvlan0 up

ip -o addr show dev macvlan0
echo "macvlan0 is up. If you change .env, rerun this script."