#!/bin/sh
echo "Starting MediaMTX..."
/mediamtx /mediamtx.yml &
MEDIAMTX_PID=$!
sleep 2
echo "Starting ONVIF server..."
node main.js /onvif.yaml &
ONVIF_PID=$!

wait $MEDIAMTX_PID $ONVIF_PID
