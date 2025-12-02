#!/bin/bash
# Howdy Camera Stream Script
# Streams the front camera to a v4l2loopback device for Howdy facial recognition
# The front camera (OV5693) is streamed to /dev/video33

set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo)"
  exit 1
fi

# Check if video33 exists
if [ ! -e /dev/video33 ]; then
    echo "ERROR: /dev/video33 does not exist!"
    echo "Please run: sudo ./scripts/setup-howdy-loopback.sh"
    exit 1
fi

# Kill any existing streams to video33
pkill -f "v4l2sink device=/dev/video33" 2>/dev/null || true
sleep 1

echo "[HOWDY-STREAM] Starting front camera stream for Howdy..."
echo "[HOWDY-STREAM] Camera: \\SB_.PC00.I2C3.CAMF (OV5693)"
echo "[HOWDY-STREAM] Output: /dev/video33"

# Start GStreamer pipeline
# Note: Using BGR format which OpenCV prefers
# Camera name must be: \_SB_.PC00.I2C3.CAMF (with leading backslash)
gst-launch-1.0 -q libcamerasrc camera-name='\_SB_.PC00.I2C3.CAMF' \
    ! queue \
    ! video/x-raw,width=640,height=480,framerate=30/1 \
    ! videoflip method=rotate-180 \
    ! videoconvert \
    ! video/x-raw,format=BGR \
    ! v4l2sink device=/dev/video33 &

STREAM_PID=$!
echo "[HOWDY-STREAM] Stream started (PID: $STREAM_PID)"
echo "$STREAM_PID" > /tmp/howdy_camera_stream.pid

# Wait for the stream to initialize
sleep 2

# Check if stream is still running
if ps -p $STREAM_PID > /dev/null; then
    echo "[HOWDY-STREAM] Stream is running successfully"
    echo "[HOWDY-STREAM] You can now use: sudo howdy add"
else
    echo "[HOWDY-STREAM] ERROR: Stream failed to start"
    exit 1
fi

# Keep the script running
wait $STREAM_PID
