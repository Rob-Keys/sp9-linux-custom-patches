#!/bin/bash
# Install GStreamer recorder for Howdy
# This allows Howdy to open the camera on-demand instead of streaming 24/7

set -e

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root: sudo ./install-howdy-gstreamer.sh"
  exit 1
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "========================================="
echo "  Howdy GStreamer Recorder Setup"
echo "========================================="
echo
echo "This installs a custom GStreamer recorder that lets"
echo "Howdy open the camera ONLY when needed (no 24/7 streaming)."
echo

# Check if Howdy is installed
if [ ! -d "/usr/lib/security/howdy" ]; then
    echo "ERROR: Howdy is not installed!"
    echo "Please install Howdy first: sudo apt install howdy"
    exit 1
fi

# Check for required Python packages
echo "[1/4] Checking dependencies..."
if ! python3 -c "import gi; gi.require_version('Gst', '1.0')" 2>/dev/null; then
    echo "  ! Installing python3-gi..."
    apt-get update
    apt-get install -y python3-gi gir1.2-gstreamer-1.0
fi
echo "  ✓ Dependencies installed"

echo
echo "[2/4] Installing GStreamer recorder..."
# Copy our custom recorder to Howdy's recorders directory
cp "$SCRIPT_DIR/gstreamer_reader.py" /usr/lib/security/howdy/recorders/
chmod 644 /usr/lib/security/howdy/recorders/gstreamer_reader.py

# Patch video_capture.py to recognize the gstreamer plugin
"$SCRIPT_DIR/scripts/howdy/patch-howdy-video-capture.sh"

echo "  ✓ Recorder installed and video_capture.py patched"

echo
echo "[3/4] Updating Howdy configuration..."
# Update config to use gstreamer recorder
sed -i 's/^recording_plugin = .*/recording_plugin = gstreamer/' /usr/lib/security/howdy/config.ini

# Set a dummy device_path (required by Howdy but not used by our recorder)
sed -i 's|^device_path = .*|device_path = /dev/null|' /usr/lib/security/howdy/config.ini

# Ensure IR is not required
sed -i 's/^require_ir = .*/require_ir = false/' /usr/lib/security/howdy/config.ini

echo "  ✓ Configuration updated"

echo
echo "[4/4] Stopping camera streaming service (if running)..."
if systemctl is-active --quiet howdy-camera.service 2>/dev/null; then
    systemctl stop howdy-camera.service
    systemctl disable howdy-camera.service
    echo "  ✓ Streaming service stopped"
else
    echo "  ✓ No streaming service running"
fi

echo
echo "========================================="
echo "  Installation Complete!"
echo "========================================="
echo
echo "Howdy will now open the camera ONLY when you:"
echo "  - Run 'sudo' commands"
echo "  - Log in"
echo "  - Unlock your screen"
echo
echo "The camera LED will turn on briefly during authentication."
echo
echo "Next steps:"
echo "  1. Add your face: sudo howdy add"
echo "  2. Test: sudo howdy test"
echo "  3. Try: sudo ls"
echo
