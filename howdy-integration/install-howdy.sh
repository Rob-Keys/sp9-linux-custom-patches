#!/bin/bash
# Installation script for Howdy camera integration
# This script sets up the Surface Pro 9 front camera to work with Howdy

set -e

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root: sudo ./install-howdy.sh"
  exit 1
fi

echo "========================================="
echo "  Howdy Camera Integration Setup"
echo "========================================="
echo

# Get the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "[1/5] Checking v4l2loopback setup..."
if [ ! -e /dev/video33 ]; then
    echo "  ! /dev/video33 not found, running setup script..."
    "$SCRIPT_DIR/scripts/howdy/setup-howdy-loopback.sh"
else
    echo "  ✓ /dev/video33 exists"
fi

echo
echo "[2/5] Configuring Howdy to use /dev/video33..."
# Update Howdy config to use video33
HOWDY_CONFIG="/usr/lib/security/howdy/config.ini"
if [ -f "$HOWDY_CONFIG" ]; then
    sed -i 's/^device_path = .*/device_path = \/dev\/video33/' "$HOWDY_CONFIG"
    echo "  ✓ Howdy config updated"
else
    echo "  ✗ ERROR: Howdy config not found at $HOWDY_CONFIG"
    exit 1
fi

echo
echo "[3/5] Installing systemd service..."
# Copy and enable systemd service
cp "$SCRIPT_DIR/howdy-camera.service" /etc/systemd/system/
systemctl daemon-reload
echo "  ✓ Service installed"

echo
echo "[4/5] Starting camera stream..."
# Start the service
systemctl enable howdy-camera.service
systemctl start howdy-camera.service
sleep 3
echo "  ✓ Camera stream started"

echo
echo "[5/5] Checking service status..."
if systemctl is-active --quiet howdy-camera.service; then
    echo "  ✓ Service is running"
else
    echo "  ✗ Service failed to start"
    echo "  Check logs with: sudo journalctl -u howdy-camera.service -f"
    exit 1
fi

echo
echo "========================================="
echo "  Installation Complete!"
echo "========================================="
echo
echo "Next steps:"
echo "  1. Add your face model: sudo howdy add"
echo "  2. Test authentication: sudo howdy test"
echo "  3. View logs: sudo journalctl -u howdy-camera.service -f"
echo
echo "To stop the camera stream:"
echo "  sudo systemctl stop howdy-camera.service"
echo
echo "To disable auto-start on boot:"
echo "  sudo systemctl disable howdy-camera.service"
echo
