#!/bin/bash
# Patch Howdy's video_capture.py to support GStreamer recorder

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

VIDEO_CAPTURE="/usr/lib/security/howdy/recorders/video_capture.py"

# Check if already patched
if grep -q "gstreamer_reader" "$VIDEO_CAPTURE"; then
    echo "Already patched!"
    exit 0
fi

# Backup original
cp "$VIDEO_CAPTURE" "$VIDEO_CAPTURE.bak"

# Add gstreamer support before the else clause (line 113)
# We'll insert after the pyv4l2 block and before the else
sed -i '112 a\
\	elif self.config.get("video", "recording_plugin") == "gstreamer":\
\		# Set the capture source for gstreamer\
\		from recorders.gstreamer_reader import gstreamer_reader\
\		self.internal = gstreamer_reader(\
\			self.config.get("video", "device_path"),\
\			camera_name='"'"'\\\\_SB_.PC00.I2C3.CAMF'"'"'  # Front camera\
\		)\
' "$VIDEO_CAPTURE"

echo "Patched successfully!"
echo "Backup saved to: $VIDEO_CAPTURE.bak"
