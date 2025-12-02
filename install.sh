#!/bin/bash
set -e

echo "=== Surface Pro 9 Camera Setup & Repair ==="
echo ""
echo "This script will install or repair your Surface Pro 9 camera setup."
echo "It can be run multiple times safely to fix any issues."
echo ""

# Check if running as root for module installation
if [ "$EUID" -eq 0 ]; then
    echo "Please run without sudo. Script will ask for sudo when needed."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KERNEL_VERSION=$(uname -r)

# Detect if this is a repair (app already installed)
REPAIR_MODE=false
if [ -f "$HOME/.local/bin/surface-camera" ]; then
    REPAIR_MODE=true
    echo "ℹ️  Existing installation detected - running in REPAIR mode"
    echo ""
fi

echo "[1/6] Installing/updating udev rules..."
sudo cp "$SCRIPT_DIR/99-surface-cameras.rules" /etc/udev/rules.d/
sudo udevadm control --reload-rules
sudo udevadm trigger
echo "✓ Udev rules installed"

echo ""
echo "[2/6] Installing/updating patched kernel modules..."
if [ -d "$SCRIPT_DIR/modules/$KERNEL_VERSION" ]; then
    sudo cp "$SCRIPT_DIR/modules/$KERNEL_VERSION/"*.ko /lib/modules/$KERNEL_VERSION/kernel/drivers/media/i2c/ 2>/dev/null || true
    sudo depmod -a
    echo "✓ Modules installed for kernel $KERNEL_VERSION"
else
    echo "⚠️  WARNING: No prebuilt modules for kernel $KERNEL_VERSION"
    echo "   You may need to build them from source or use stock kernel modules"
fi

echo ""
echo "[3/6] Checking Python dependencies..."
if ! python3 -c "import gi" 2>/dev/null; then
    echo "Installing python3-gi and GStreamer plugins..."
    sudo apt-get update -qq
    sudo apt-get install -y python3-gi python3-gi-cairo gir1.2-gtk-3.0 \
        gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-libav
    echo "✓ Python dependencies installed"
else
    echo "✓ Python dependencies already installed"
fi

echo ""
echo "[4/6] Installing/updating camera app..."
mkdir -p ~/.local/bin
# Copy the app
cp "$SCRIPT_DIR/surface-camera.py" ~/.local/bin/surface-camera

# Copy the bin directory with scripts
mkdir -p ~/.local/bin/bin
cp "$SCRIPT_DIR/bin/camera-prep.sh" ~/.local/bin/bin/
cp "$SCRIPT_DIR/bin/camera-stream.sh" ~/.local/bin/bin/
cp "$SCRIPT_DIR/bin/camera-cleanup.sh" ~/.local/bin/bin/
cp "$SCRIPT_DIR/bin/camera-health-check.sh" ~/.local/bin/bin/

chmod +x ~/.local/bin/surface-camera
chmod +x ~/.local/bin/bin/*.sh

# Create/update desktop entry
mkdir -p ~/.local/share/applications
cat > ~/.local/share/applications/surface-camera.desktop << DESKTOP
[Desktop Entry]
Name=Surface Camera
Comment=Camera app for Surface Pro 9
Exec=$HOME/.local/bin/surface-camera
Icon=camera-web
Terminal=false
Type=Application
Categories=AudioVideo;Video;
DESKTOP

echo "✓ Camera app and scripts installed to ~/.local/bin/"

echo ""
echo "[5/6] Configuring camera power management..."
# Set cameras to runtime PM mode (auto)
FRONT_DEV="/sys/bus/i2c/devices/i2c-OVTI5693:00/power/control"
if [ -f "$FRONT_DEV" ]; then
    echo auto | sudo tee "$FRONT_DEV" > /dev/null
    echo "✓ Front camera: runtime PM enabled"
else
    echo "⚠️  Warning: Front camera device not found"
fi

REAR_DEV="/sys/bus/i2c/devices/i2c-OVTID858:00/power/control"
if [ -f "$REAR_DEV" ]; then
    echo auto | sudo tee "$REAR_DEV" > /dev/null
    echo "✓ Rear camera: runtime PM enabled"
else
    echo "⚠️  Warning: Rear camera device not found"
fi

echo ""
echo "[6/6] Resetting media controller..."
media-ctl -d /dev/media0 -r 2>/dev/null && echo "✓ Media links reset" || echo "⚠️  Could not reset media links (this is OK)"

echo ""
if [ "$REPAIR_MODE" = true ]; then
    echo "=== Repair Complete ==="
    echo ""
    echo "✅ Camera installation has been repaired and updated!"
    echo "   • Udev rules corrected"
    echo "   • Kernel modules refreshed"
    echo "   • App and scripts updated"
    echo "   • Power management configured"
    echo "   • Media controller reset"
else
    echo "=== Installation Complete ==="
    echo ""
    echo "✅ Surface Pro 9 cameras are now installed and configured!"
fi
echo ""
echo "📱 Launch the camera app:"
echo "   • Command: surface-camera"
echo "   • App menu: Search for 'Surface Camera'"
echo ""
echo "🧪 Test the cameras:"
echo "   • Front: scripts/test-front-camera.sh"
echo "   • Rear:  scripts/test-rear-camera.sh"
echo ""
echo "💡 Note: Cameras show 'suspended' when idle - this is normal!"
echo "   They wake automatically when accessed by applications."
echo ""
if [ "$REPAIR_MODE" = true ]; then
    echo "🔧 If you still have issues, try rebooting to ensure all"
    echo "   kernel modules and udev rules are properly loaded."
fi