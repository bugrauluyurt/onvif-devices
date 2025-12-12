#!/usr/bin/env bash
set -euo pipefail

# Detect script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"

# Source .env file if it exists
if [ -f "$ENV_FILE" ]; then
  source "$ENV_FILE"
fi

# fallback autodetect if not set
if [ -z "${PARENT_IF:-}" ]; then
  PARENT_IF="$(ip route show default | awk '{print $5}' | head -n1)"
fi

if ! ip link show "$PARENT_IF" >/dev/null 2>&1; then
  echo "Parent interface '$PARENT_IF' not found. Set PARENT_IF in .env (e.g., eth0)." >&2
  exit 1
fi

# Check if HOST_SHIM_IP is set (optional for debugging)
if [ -n "${HOST_SHIM_IP:-}" ]; then
  echo "Using parent interface: $PARENT_IF"
  echo "Creating macvlan0 shim at: ${HOST_SHIM_IP}"
  echo "(Note: Host shim is optional - only needed to access cameras from this host)"
  echo

  sudo ip link add macvlan0 link "$PARENT_IF" type macvlan mode bridge 2>/dev/null || true
  sudo ip addr add "$HOST_SHIM_IP" dev macvlan0 2>/dev/null || true
  sudo ip link set macvlan0 up

  ip -o addr show dev macvlan0
  echo
  echo "macvlan0 is up. If you change .env, rerun this script."
else
  echo "HOST_SHIM_IP not set in .env - skipping host shim creation."
  echo
  echo "Note: With the sidecar architecture, the host shim is optional."
  echo "RTSP streams are served directly from each camera's macvlan IP."
  echo "Other machines on the network can access the cameras directly."
  echo
  echo "If you need to access cameras FROM THIS HOST, add HOST_SHIM_IP to .env:"
  echo "  HOST_SHIM_IP=10.0.0.250/24"
  echo "Then rerun this script."
fi
