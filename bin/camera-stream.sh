#!/bin/bash
# CAMERA STREAM SCRIPT
# Starts GStreamer pipelines to stream cameras to v4l2loopback devices.
# Front -> /dev/video10
# Rear  -> /dev/video11

# Ensure we are running with root privileges for hardware access
if [ "$EUID" -ne 0 ]; then 
  echo "Please run as root (sudo)"
  exit 1
fi

echo "[STREAM] Initializing GStreamer pipelines..."

# Ensure no lingering pipelines
pkill -f "gst-launch.*libcamerasrc" 2>/dev/null

# Define PIDs file
PID_FILE="/tmp/surface_camera_pids"
rm -f "$PID_FILE"

# --- Front Camera ---
echo "Starting Front Camera..."
gst-launch-1.0 libcamerasrc camera-name='\_SB_.PC00.I2C3.CAMF' \
    ! queue \
    ! video/x-raw,width=1280,height=720,framerate=30/1 \
    ! videoflip method=rotate-180 \
    ! videoconvert \
    ! video/x-raw,format=YUY2 \
    ! v4l2sink device=/dev/video10 >/tmp/cam_front.log 2>&1 &
PID_FRONT=$!
echo "FRONT:$PID_FRONT" >> "$PID_FILE"
echo "Front Camera running on /dev/video10 (PID: $PID_FRONT)"

# --- Rear Camera ---
echo "Starting Rear Camera..."
gst-launch-1.0 libcamerasrc camera-name='\_SB_.PC00.I2C2.CAMR' \
    ! queue \
    ! video/x-raw,width=1280,height=720,framerate=30/1 \
    ! videoflip method=rotate-180 \
    ! videoconvert \
    ! video/x-raw,format=YUY2 \
    ! v4l2sink device=/dev/video11 >/tmp/cam_rear.log 2>&1 &
PID_REAR=$!
echo "REAR:$PID_REAR" >> "$PID_FILE"
echo "Rear Camera running on /dev/video11 (PID: $PID_REAR)"

echo "[STREAM] Pipelines active."
