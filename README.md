# ONVIF Device Simulation

A Docker-based setup for creating virtual ONVIF cameras that can be discovered and accessed as real IP cameras on your local network. This project uses macvlan networking to give each virtual camera its own IP address and MAC address, making them appear as physical devices to ONVIF clients.

## Features

- Virtual ONVIF cameras with unique IP addresses and MAC addresses
- RTSP video streaming using MediaMTX
- Full ONVIF protocol support for device discovery and control
- Configurable video quality settings (high/low quality streams)
- Support for multiple camera instances

## Prerequisites

- Docker and Docker Compose
- Linux host with network interface access
- For ARM devices (Raspberry Pi): ARM64-compatible Docker image
- Video files for streaming (MP4 format recommended)
- arp-scan for network discovery:
  - Ubuntu/Debian: `sudo apt-get install arp-scan`
  - macOS: `brew install arp-scan`
  - RHEL/CentOS: `sudo yum install arp-scan`

## Installation

### 1. Build ONVIF Server (Required for ARM devices)

If you're running on ARM devices like Raspberry Pi, you need to build the ONVIF server image:

```bash
git clone https://github.com/daniela-hase/onvif-server.git
cd onvif-server
sudo docker buildx build --platform linux/arm64 -t onvif-server:arm64-local --load .
```

### 2. Clone and Setup Project

```bash
git clone <this-repository>
cd onvif-devices
```

### 3. Generate Network Configuration

Use the configuration generator to automatically detect your network and suggest settings:

```bash
# Run with sudo for best network scanning
sudo ./scripts/generate-config.sh

# Or specify options
sudo ./scripts/generate-config.sh -i wlan0 -c 3 -w

# See all options
./scripts/generate-config.sh -h
```

This script will:
- Automatically detect your network subnet and gateway
- Scan for used IP addresses using arp-scan
- Suggest available IPs for cameras and host interface
- Generate MAC addresses with the 8C:1F:64:A2 prefix
- Optionally write the configuration to `.env` file

## Configuration

### Network Configuration

The configuration generator creates a `.env` file, but you can also edit it manually:

```bash
# Ethernet NIC for macvlan
PARENT_IF=eth0

# Your LAN
LAN_SUBNET=10.0.0.0/24
LAN_GATEWAY=10.0.0.1

# Host-side macvlan shim (unused IP you confirmed free)
HOST_SHIM_IP=10.0.0.250/24

# Virtual ONVIF devices (unique IPs + MACs)
CAM1_IP=10.0.0.231
CAM1_MAC=8C:1F:64:A2:00:01

CAM2_IP=10.0.0.232
CAM2_MAC=8C:1F:64:A2:00:02
```

**Important**: Make sure the camera IPs are static or adjust your DHCP pool from your router to prevent IP conflicts.

⚠️ **Critical**: After generating or updating your `.env` file, you **MUST** update the MAC addresses in the ONVIF camera configuration files to match the generated values:

- Update `mac:` field in `onvif-cam1-macvlan.yaml` with the `CAM1_MAC` value from `.env`
- Update `mac:` field in `onvif-cam2-macvlan.yaml` with the `CAM2_MAC` value from `.env`
- For additional cameras, update `onvif-cam{N}-macvlan.yaml` with corresponding `CAM{N}_MAC` values

**Example**: If your `.env` contains `CAM1_MAC=8C:1F:64:A2:01:01`, then `onvif-cam1-macvlan.yaml` should have:
```yaml
onvif:
  - mac: 8C:1F:64:A2:01:01
```

Failure to update these MAC addresses will cause network conflicts and prevent the cameras from working properly.

### Video Preparation

Convert your video files to ONVIF-compatible format using FFmpeg:

```bash
ffmpeg -i /path/to/input/video.mp4 -vf scale=1280:720,fps=15 -pix_fmt yuv420p \
  -c:v libx264 -preset slow -crf 23 -g 30 -sc_threshold 0 \
  -c:a aac -ar 48000 -ac 1 -b:a 96k /path/to/output/video_720p_h264_aac.mp4
```

This command:
- Scales video to 1280x720 (common ONVIF camera resolution)
- Sets frame rate to 15 fps
- Uses H.264 video codec with AAC audio
- Optimizes for streaming compatibility

Place your converted video files in `/home/pi/Videos/` (or update the volume mount in docker-compose.yml).

## Setup and Deployment

### 1. Configure Macvlan Network

```bash
./scripts/macvlan-setup.sh
```

This script creates the macvlan interface needed for containers to have unique IP addresses.

**Note**: If you haven't generated the `.env` file yet, run the configuration generator first:
```bash
sudo ./scripts/generate-config.sh
```

⚠️ **Important**: Before starting services, ensure you have updated the MAC addresses in the ONVIF camera configuration files (`onvif-cam1-macvlan.yaml`, `onvif-cam2-macvlan.yaml`) to match the `CAM1_MAC`, `CAM2_MAC` values from your `.env` file.

### 2. Start Services

```bash
docker compose -f docker-compose.macvlan.yml --env-file .env up -d
```

### 3. Verify Deployment

Check if containers are running:

```bash
docker compose -f docker-compose.macvlan.yml ps
```

View logs:

```bash
docker compose -f docker-compose.macvlan.yml logs -f
```

## Usage

### Accessing ONVIF Cameras

Once deployed, your virtual cameras will be accessible at:

- **Camera 1**: `http://10.0.0.231` (or your configured CAM1_IP)
- **Camera 2**: `http://10.0.0.232` (or your configured CAM2_IP)

### RTSP Streams

- **Camera 1 High Quality**: `rtsp://10.0.0.250:8554/cam1`
- **Camera 1 Low Quality**: `rtsp://10.0.0.250:8554/cam1` (same stream, quality negotiated)
- **Camera 2 High Quality**: `rtsp://10.0.0.250:8554/cam2`
- **Camera 2 Low Quality**: `rtsp://10.0.0.250:8554/cam2`

### ONVIF Discovery

Use ONVIF-compatible software to discover devices:
- ONVIF Device Manager
- VLC Media Player
- Security camera software
- Custom ONVIF clients

## Project Structure

```
onvif-devices/
├── scripts/
│   ├── generate-config.sh            # Network configuration generator
│   ├── macvlan-setup.sh              # Network setup script
│   └── macvlan-cleanup.sh            # Network cleanup script
├── .env                              # Network configuration
├── docker-compose.macvlan.yml        # Main Docker Compose file
├── mediamtx.yml                      # RTSP server configuration
├── onvif-cam1-macvlan.yaml          # Camera 1 ONVIF config
├── onvif-cam2-macvlan.yaml          # Camera 2 ONVIF config
├── CLAUDE.md                         # Development guidance
└── README.md                         # This file
```

## Configuration Files Explained

- **`.env`**: Network settings including IP addresses and MAC addresses
- **`docker-compose.macvlan.yml`**: Defines services and macvlan network configuration
- **`mediamtx.yml`**: MediaMTX server settings for RTSP streaming
- **`onvif-cam*-macvlan.yaml`**: Individual camera configurations with ONVIF parameters
- **`scripts/generate-config.sh`**: Script to automatically generate network configuration
- **`scripts/macvlan-setup.sh`**: Script to create macvlan network interface
- **`scripts/macvlan-cleanup.sh`**: Script to remove macvlan network interface

## Troubleshooting

### Network Issues

1. **Containers can't reach network**:
   - Verify macvlan interface is up: `ip addr show macvlan0`
   - Check if parent interface exists: `ip link show eth0`

2. **IP conflicts**:
   - Ensure camera IPs don't conflict with DHCP range
   - Use static IPs or configure DHCP reservations

3. **Can't access cameras from host**:
   - Host needs macvlan shim interface (created by scripts/macvlan-setup.sh)
   - Verify HOST_SHIM_IP is accessible: `ping 10.0.0.250`

### Service Issues

1. **ONVIF server not responding**:
   - Check if ARM64 image was built correctly
   - Verify container logs: `docker logs onvif-cam1`

2. **No video streams**:
   - Ensure video files exist in `/home/pi/Videos/`
   - Check MediaMTX logs: `docker logs mediamtx`
   - Verify FFmpeg is processing files correctly

### Commands for Debugging

```bash
# Check container status
docker compose -f docker-compose.macvlan.yml ps

# View all logs
docker compose -f docker-compose.macvlan.yml logs

# Check specific service
docker logs mediamtx
docker logs onvif-cam1

# Test network connectivity
ping 10.0.0.231  # Camera 1
ping 10.0.0.232  # Camera 2
ping 10.0.0.250  # MediaMTX host

# Clean up macvlan interface
./scripts/macvlan-cleanup.sh

# Recreate macvlan interface
./scripts/macvlan-setup.sh

# Stop and restart services
docker compose -f docker-compose.macvlan.yml down
docker compose -f docker-compose.macvlan.yml up -d
```

## Stopping Services

```bash
docker compose -f docker-compose.macvlan.yml down
```

This will stop and remove all containers while preserving the macvlan network interface.