#!/bin/bash
# Camera health check script
# Verifies camera hardware is accessible and operational

FRONT_CAMERA_I2C="i2c-OVTI5693:00"
REAR_CAMERA_I2C="i2c-OVTID858:00"

check_camera() {
    local camera_id=$1
    local camera_name=$2
    local dev_path="/sys/bus/i2c/devices/${camera_id}"

    if [ ! -d "$dev_path" ]; then
        echo "ERROR: ${camera_name} device not found at ${dev_path}"
        return 1
    fi

    local status_path="${dev_path}/power/runtime_status"
    if [ -f "$status_path" ]; then
        local status=$(cat "$status_path" 2>/dev/null)
        echo "${camera_name}: ${status}"

        # Try to ensure camera is in a good state
        local control_path="${dev_path}/power/control"
        if [ -w "$control_path" ]; then
            echo "auto" > "$control_path" 2>/dev/null || true
        fi
    fi

    return 0
}

echo "=== Camera Hardware Health Check ==="
check_camera "$FRONT_CAMERA_I2C" "Front Camera"
check_camera "$REAR_CAMERA_I2C" "Rear Camera"

# Check if libcamera can enumerate cameras
if command -v libcamera-hello &> /dev/null; then
    echo ""
    echo "=== libcamera device enumeration ==="
    timeout 2 libcamera-hello --list-cameras 2>&1 | head -20 || echo "libcamera enumeration failed or timed out"
fi

exit 0
