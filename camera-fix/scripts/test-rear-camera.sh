#!/bin/bash
echo "Testing Surface Pro 9 rear camera (ov13858)..."
echo "Press Ctrl+C to stop"
gst-launch-1.0 libcamerasrc camera-name='\\_SB_.PC00.I2C2.CAMR' \
    ! queue \
    ! video/x-raw,width=1280,height=720 \
    ! videoflip method=rotate-180 \
    ! videoconvert \
    ! queue \
    ! ximagesink sync=false
