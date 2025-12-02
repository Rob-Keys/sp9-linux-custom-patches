#!/bin/bash
# Fix camera initialization issues
# This script corrects the power management settings and reinstalls udev rules

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Surface Pro 9 Camera Initialization Fix ==="
echo ""
echo "This script will:"
echo "  1. Update udev rules with correct power management"
echo "  2. Set cameras to runtime PM mode"
echo "  3. Reset media controller to clear stale state"
echo ""

# Check if we need sudo
if [ "$EUID" -eq 0 ]; then
    echo "Please run without sudo. Script will ask for sudo when needed."
    exit 1
fi

echo "[1/3] Installing corrected udev rules..."
sudo cp "$SCRIPT_DIR/99-surface-cameras.rules" /etc/udev/rules.d/
sudo udevadm control --reload-rules
sudo udevadm trigger
echo "✓ Udev rules updated"

echo ""
echo "[2/3] Configuring camera power management..."

# Front Camera - Set to auto mode for runtime PM
FRONT_DEV="/sys/bus/i2c/devices/i2c-OVTI5693:00/power/control"
if [ -f "$FRONT_DEV" ]; then
    echo auto | sudo tee "$FRONT_DEV" > /dev/null
    echo "✓ Front camera: runtime PM enabled (auto)"
else
    echo "⚠ Warning: Front camera device not found at $FRONT_DEV"
fi

# Rear Camera - Set to auto mode for runtime PM
REAR_DEV="/sys/bus/i2c/devices/i2c-OVTID858:00/power/control"
if [ -f "$REAR_DEV" ]; then
    echo auto | sudo tee "$REAR_DEV" > /dev/null
    echo "✓ Rear camera: runtime PM enabled (auto)"
else
    echo "⚠ Warning: Rear camera device not found at $REAR_DEV"
fi

echo ""
echo "[3/3] Resetting media controller..."
media-ctl -d /dev/media0 -r 2>/dev/null && echo "✓ Media links reset" || echo "⚠ Warning: Failed to reset media links"

echo ""
echo "=== Fix Complete ==="
echo ""
echo "Camera initialization has been corrected. The cameras are now configured"
echo "with runtime power management, which means they will:"
echo "  • Automatically wake up when accessed by an application"
echo "  • Automatically suspend when idle to save power"
echo "  • No longer conflict with incorrect power state commands"
echo ""
echo "You can now test the cameras:"
echo "  • GUI app: surface-camera"
echo "  • Front camera test: scripts/test-front-camera.sh"
echo "  • Rear camera test: scripts/test-rear-camera.sh"
echo ""
echo "Note: It's normal for cameras to show 'suspended' status when idle."
echo "They will automatically wake when an application accesses them."
