# Surface Pro 9 Camera Support for Linux

Enable front (OV5693) and rear (OV13858) cameras on Surface Pro 9 running Linux with patched kernel modules.

## Quick Start

```bash
# Install
./install.sh

# Test cameras
./scripts/test-front-camera.sh
./scripts/test-rear-camera.sh

# Run simple camera app
./scripts/camera_app_simple.py

# Run full GUI app (requires python3-gi)
surface-camera
```

## Status

| Component | Status | Notes |
|-----------|--------|-------|
| Front Camera (OV5693) | ✅ Working | 5MP, I2C3 |
| Rear Camera (OV13858) | ✅ Working | 13MP, I2C2 |
| IR Sensor | ❌ Not working | ACPI error |

## Requirements

- **Kernel:** linux-surface 6.17+
- **OS:** Ubuntu 24.04+ or similar
- **libcamera:** 0.5.2+ with IPU6 support
- **GStreamer:** gstreamer1.0-plugins-base, gstreamer1.0-plugins-good

## What Gets Installed

- Patched kernel modules (ov5693, ov13858, ipu-bridge, int3472) in `/lib/modules/$(uname -r)/`
- udev rules for camera power management in `/etc/udev/rules.d/`
- Camera app binary in `~/.local/bin/surface-camera`
- Desktop entry in `~/.local/share/applications/`

## Known Issues

1. **Upside-down video:** Add `videoflip method=rotate-180` to GStreamer pipeline
2. **Green tint:** Missing IPA calibration files (cosmetic only)
3. **IR sensor:** INT3472:01 ACPI error prevents initialization
4. **Kernel updates:** Modules must be reinstalled after kernel updates

## File Structure

```
sp-cam/
├── install.sh              # Main installation script
├── 99-surface-cameras.rules # udev rules for power management
├── modules/                # Prebuilt kernel modules by kernel version
├── bin/                    # Helper scripts for GUI app
│   ├── camera-prep.sh
│   ├── camera-stream.sh
│   └── camera-cleanup.sh
├── scripts/
│   ├── camera_app_simple.py    # Simple CLI camera app (no dependencies)
│   ├── test-front-camera.sh    # Test front camera
│   └── test-rear-camera.sh     # Test rear camera
└── surface-camera.py       # Full GUI app (requires GTK3/GStreamer)
```

## Technical Details

### Patches Applied

1. **ov5693.c**: Added OVTI5693 ACPI ID, reduced regulator requirements
2. **ov13858.c**: Added OVTID858 ACPI ID, power management via regulators/clocks
3. **int3472-discrete.c**: Handle GPIO types 0x08 (power rail) and 0x10 (unknown)
4. **ipu-bridge.c**: Added sensor configs for OVTI5693 and OVTID858

### Camera Identification

```bash
# List cameras
libcamera-hello --list-cameras

# Front camera
Camera 0: \\_SB_.PC00.I2C3.CAMF (ov5693)

# Rear camera
Camera 1: \\_SB_.PC00.I2C2.CAMR (ov13858)
```

### Power Management

The INT3472 discrete power controller provides:
- Power rails (GPIO type 0x08 → regulator)
- Clock enable (CLK type)
- Privacy LED control (GPIO type 0x0c)
- Unknown GPIO (type 0x10 → skipped)

## Camera App Usage Notes

### CRITICAL: Camera Resource Management
- **DO NOT manually power cycle cameras** via sysfs - let the kernel handle power management
- **Close apps properly** - don't force-kill, as it leaves camera resources locked
- Only one app can access a camera at a time
- Photo capture temporarily pauses the preview (this is normal)

### Debug Logging
All camera operations are logged to `/tmp/surface_camera_debug.log` for troubleshooting.

### Known Camera App Issues
1. **Photo capture disabled**: Photo capture causes camera resource conflicts and breaks the preview. Feature is disabled for now. Use screenshot tool instead.
2. **Camera won't start after crash**: Restart the app or reboot if camera resources are stuck
3. **Inconsistent startup**: Sometimes camera shows black/grey on first start - switching cameras or restarting usually fixes it

## Troubleshooting

### Camera not detected
```bash
# Check I2C devices
i2cdetect -l | grep OVTI

# Check power status
cat /sys/bus/i2c/devices/i2c-OVTI5693:00/power/runtime_status
cat /sys/bus/i2c/devices/i2c-OVTID858:00/power/runtime_status

# Check kernel logs
sudo dmesg | grep -E "ov5693|ov13858|ipu6|int3472"
```

### Camera app shows grey/blank screen
```bash
# Check debug log
tail -50 /tmp/surface_camera_debug.log

# Restart the app properly (close window, don't Ctrl+C)
# If stuck, kill all camera processes:
pkill -9 gst-launch
pkill -9 libcamera
```

### Module loading issues
```bash
# Reload modules
sudo modprobe -r ov5693 ov13858
sudo modprobe ov5693 ov13858

# Check module info
modinfo ov5693 | grep -E "filename|vermagic"
```

### After kernel update
```bash
# Reinstall modules
./install.sh
```

## Building from Source

If prebuilt modules don't match your kernel:

```bash
# Install build dependencies
sudo apt install build-essential linux-headers-$(uname -r)

# Get kernel source matching your version
# Apply patches from this repo to:
#   drivers/media/i2c/ov5693.c
#   drivers/media/i2c/ov13858.c
#   drivers/media/pci/intel/ipu-bridge.c
#   drivers/platform/x86/intel/int3472/discrete.c

# Build modules
make -C /lib/modules/$(uname -r)/build M=drivers/media/i2c modules
make -C /lib/modules/$(uname -r)/build M=drivers/media/pci/intel modules
make -C /lib/modules/$(uname -r)/build M=drivers/platform/x86/intel modules

# Copy to modules/ directory
mkdir -p modules/$(uname -r)
cp drivers/media/i2c/*.ko modules/$(uname -r)/
# etc...
```

## Credits

- Based on [linux-surface PR #1867](https://github.com/linux-surface/linux-surface/pull/1867) by @toorajtaraz
- [linux-surface](https://github.com/linux-surface/linux-surface) project
- Intel IPU6 camera stack

## License

GPL-2.0 (same as Linux kernel)
