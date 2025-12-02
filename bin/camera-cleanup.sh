#!/bin/bash
# CAMERA CLEANUP SCRIPT
# Stops camera streaming pipelines and cleans up processes.

echo "[CLEANUP] Stopping camera streams..."

PID_FILE="/tmp/surface_camera_pids"

if [ -f "$PID_FILE" ]; then
    while read -r line; do
        PID=$(echo "$line" | cut -d':' -f2)
        if [ -n "$PID" ]; then
            echo "Killing process $PID..."
            kill -9 "$PID" 2>/dev/null
        fi
    done < "$PID_FILE"
    rm "$PID_FILE"
fi

# Safety net: ensure all gst-launch instances related to libcamera are gone
pkill -f "gst-launch.*libcamerasrc" 2>/dev/null

echo "[CLEANUP] Cameras stopped."
