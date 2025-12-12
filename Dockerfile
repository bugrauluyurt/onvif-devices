# Stage 1: Get ONVIF app from onvif-server image
FROM ghcr.io/daniela-hase/onvif-server:latest AS onvif-source

# Stage 2: Build combined image using Alpine-based mediamtx
FROM bluenviron/mediamtx:latest-ffmpeg

# Install Node.js from Alpine packages (multi-arch)
RUN apk add --no-cache nodejs

# Copy ONVIF server application (JS code, arch-independent)
COPY --from=onvif-source /app /onvif-app

WORKDIR /onvif-app

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
