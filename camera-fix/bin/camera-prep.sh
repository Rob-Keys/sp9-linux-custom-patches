#!/bin/bash
# CAMERA PREP SCRIPT
# Prepares the Surface Pro 9 cameras for use.
# Actions: Stops existing processes, reloads kernel modules, power cycles hardware.

# Ensure we are running with root privileges for hardware access
if [ "$EUID" -ne 0 ]; then 
  echo "Please run as root (sudo)"
  exit 1
fi

echo "[PREP] Stopping existing camera processes..."
pkill -9 -f libcamera 2>/dev/null
pkill -9 -f gst-launch 2>/dev/null


echo "[PREP] Reloading sensor kernel modules..."
# Unload in reverse order of dependency if possible, though these are independent usually
rmmod ov5693 ov13858 2>/dev/null
modprobe ov5693
modprobe ov13858
# Allow time for modules to initialize
sleep 1

echo "[PREP] Configuring camera power management..."
# Front Camera - Set to auto mode for runtime PM
FRONT_DEV="/sys/bus/i2c/devices/i2c-OVTI5693:00/power/control"
if [ -f "$FRONT_DEV" ]; then
    echo auto > "$FRONT_DEV"
    echo "Front camera: runtime PM enabled"
else
    echo "Warning: Front camera device not found at $FRONT_DEV"
fi

# Rear Camera - Set to auto mode for runtime PM
REAR_DEV="/sys/bus/i2c/devices/i2c-OVTID858:00/power/control"
if [ -f "$REAR_DEV" ]; then
    echo auto > "$REAR_DEV"
    echo "Rear camera: runtime PM enabled"
else
    echo "Warning: Rear camera device not found at $REAR_DEV"
fi

# Reset media controller links to clear any stale state
echo "[PREP] Resetting media controller links..."
media-ctl -d /dev/media0 -r 2>/dev/null || echo "Warning: Failed to reset media links"

# Allow hardware to settle
sleep 0.5

echo "[PREP] Camera initialization complete."
