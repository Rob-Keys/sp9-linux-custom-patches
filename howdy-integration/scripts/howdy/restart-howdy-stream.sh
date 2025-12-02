#!/bin/bash
# Quick script to restart the Howdy camera stream

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root: sudo ./scripts/restart-howdy-stream.sh"
  exit 1
fi

echo "Stopping howdy-camera service..."
systemctl stop howdy-camera.service

echo "Killing any lingering GStreamer processes..."
pkill -9 -f "gst-launch.*libcamera" 2>/dev/null || true
sleep 1

echo "Starting howdy-camera service..."
systemctl start howdy-camera.service

sleep 2

echo ""
echo "Service status:"
systemctl status howdy-camera.service --no-pager -l | head -20

echo ""
echo "Checking if stream is working..."
if timeout 2 v4l2-ctl -d /dev/video33 --stream-mmap --stream-count=1 2>&1 | grep -q "STREAMON"; then
    echo "✓ Stream is working!"
else
    echo "Checking recent logs..."
    journalctl -u howdy-camera.service -n 10 --no-pager
fi
