#!/bin/bash
# Setup v4l2loopback for Howdy
# This creates a second v4l2loopback device specifically for Howdy

set -e

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root: sudo ./scripts/setup-howdy-loopback.sh"
  exit 1
fi

echo "========================================="
echo "  Setting up v4l2loopback for Howdy"
echo "========================================="
echo

# Backup existing configuration
if [ -f /etc/modprobe.d/v4l2loopback.conf ]; then
    cp /etc/modprobe.d/v4l2loopback.conf /etc/modprobe.d/v4l2loopback.conf.bak
    echo "[BACKUP] Existing config saved to v4l2loopback.conf.bak"
fi

echo "[CONFIG] Creating new v4l2loopback configuration..."
# Create new configuration with 2 devices
# Device 0 (video32): exclusive_caps for compatibility (existing)
# Device 1 (video33): no exclusive_caps for Howdy (can read/write)
cat > /etc/modprobe.d/v4l2loopback.conf << 'EOF'
# v4l2loopback configuration for Surface Pro 9
# Device 0 (/dev/video32): Standard loopback with exclusive caps
# Device 1 (/dev/video33): Howdy camera (read/write capable)
options v4l2loopback devices=2 video_nr=32,33 card_label="Intel MIPI Camera","Howdy Camera" exclusive_caps=1,0
EOF

echo "[RELOAD] Reloading v4l2loopback module..."
# Unload the module
modprobe -r v4l2loopback 2>/dev/null || true
sleep 1

# Load the module with new configuration
modprobe v4l2loopback

echo "[VERIFY] Checking devices..."
sleep 1

if [ -e /dev/video33 ]; then
    echo "✓ /dev/video33 created successfully"
    v4l2-ctl -d /dev/video33 --all 2>&1 | grep -E "Card type|Capabilities" | head -6
else
    echo "✗ ERROR: /dev/video33 not created"
    exit 1
fi

echo
echo "========================================="
echo "  Setup Complete!"
echo "========================================="
echo
echo "Next steps:"
echo "  1. Run: sudo ./install-howdy.sh"
echo
