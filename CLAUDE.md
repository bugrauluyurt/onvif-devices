# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an ONVIF device simulation setup using Docker containers with macvlan networking. The project creates virtual ONVIF cameras that can be discovered and accessed as real IP cameras on a local network.

## Architecture

The setup consists of:
- **MediaMTX**: RTSP media server that serves video streams from local files
- **ONVIF Camera Containers**: Virtual ONVIF devices that simulate IP cameras with proper ONVIF protocol support
- **Macvlan Networking**: Creates virtual network interfaces allowing containers to have unique IP addresses and MAC addresses on the LAN

## Key Configuration Files

- `.env`: Network configuration (LAN subnet, gateway, device IPs and MACs)
- `docker-compose.yml`: Main Docker Compose configuration
- `Dockerfile`: Combined image build (ONVIF + MediaMTX)
- `entrypoint.sh`: Container entrypoint script
- `mediamtx-cam1.yml` / `mediamtx-cam2.yml`: MediaMTX server configuration for each camera
- `onvif-cam1-macvlan.yaml` / `onvif-cam2-macvlan.yaml`: Individual ONVIF device configurations
- `scripts/generate-config.sh`: Script to automatically generate network configuration
- `scripts/macvlan-setup.sh`: Script to create macvlan network interface
- `scripts/macvlan-cleanup.sh`: Script to remove macvlan network interface

## Common Commands

### Setup and Deployment
```bash
# Generate network configuration (run first)
sudo ./scripts/generate-config.sh

# Set up macvlan network interface (run once or after .env changes)
./scripts/macvlan-setup.sh

# Start all services
docker compose up -d

# Stop services
docker compose down

# Clean up macvlan interface
./scripts/macvlan-cleanup.sh

# View logs
docker compose logs -f
```

### Network Configuration
- Containers use macvlan networking to appear as separate devices on the LAN
- Each ONVIF camera has a unique IP address and MAC address
- Host communication requires the macvlan shim interface (macvlan0)

## Development Notes

- The ONVIF server is pulled from `ghcr.io/daniela-hase/onvif-server` during build
- Works on any architecture (ARM64, x86_64, etc.) - Node.js is installed via Alpine packages
- Use `scripts/generate-config.sh` to automatically detect network settings and generate .env file
- Video files should be placed in `/home/pi/Videos` directory (mounted as `/media` in containers)
- ONVIF devices are accessible at their configured IP addresses (CAM1_IP, CAM2_IP from .env)
- MediaMTX serves RTSP streams on port 8554 with path `/cam/realmonitor`
- arp-scan is required for network discovery (install via package manager)