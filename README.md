# Surface Pro 9 Camera Support for Linux

Enable front (OV5693) and rear (OV13858) cameras on Surface Pro 9 running Linux with patched kernel modules.

## Quick Start

```bash
# Install camera support
cd camera-fix
./install.sh

# Test cameras
./scripts/test-front-camera.sh
./scripts/test-rear-camera.sh

# Run camera app
surface-camera
```

## Status

| Component | Status | Notes |
|-----------|--------|-------|
| Front Camera (OV5693) | ✅ Working | 5MP, I2C3 |
| Rear Camera (OV13858) | ✅ Working | 13MP, I2C2 |
| IR Sensor | ❌ Not working | ACPI error |
| Howdy Integration | ✅ Working | On-demand camera access via GStreamer |

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

---

## Howdy Facial Recognition Integration

Set up Windows Hello-style facial recognition for login, sudo, and screen unlock.

### Recommended: GStreamer Integration (On-Demand)

This is the **recommended approach** - camera only opens when needed.

**Installation:**
```bash
cd howdy-integration
sudo ./install-howdy-gstreamer.sh
```

**Add your face:**
```bash
sudo howdy add
```

**Test recognition:**
```bash
sudo howdy test
```

**Benefits:**
- ✅ Camera opens only when Howdy needs it
- ✅ LED indicates when camera is active
- ✅ No background services
- ✅ Lower power consumption
- ✅ Better privacy

**How it works:** Custom GStreamer recorder integrates directly into Howdy, opening the camera on-demand and closing it immediately after authentication.

**Troubleshooting:**
```bash
# Test GStreamer pipeline
gst-launch-1.0 libcamerasrc camera-name='\_SB_.PC00.I2C3.CAMF' ! fakesink

# Test recorder directly
cd /usr/lib/security/howdy
sudo python3 -c "
from recorders.gstreamer_reader import gstreamer_reader
reader = gstreamer_reader('/dev/null')
success, frame = reader.read()
print(f'Success: {success}')
reader.release()
"
```

### Alternative: v4l2loopback Streaming (Not Recommended)

This approach streams the camera 24/7 to a v4l2loopback device.

**Installation:**
```bash
cd howdy-integration
sudo ./install-howdy.sh
```

**Why it's not recommended:**
- ❌ Camera runs continuously in the background
- ❌ Higher power consumption
- ❌ Privacy LED always on
- ❌ More complex setup
- ❌ Requires systemd service

**When to use:** Only if the GStreamer integration doesn't work for your setup.

**Control the stream:**
```bash
# Check status
sudo systemctl status howdy-camera.service

# View logs
sudo journalctl -u howdy-camera.service -f

# Restart
sudo systemctl restart howdy-camera.service

# Stop
sudo systemctl stop howdy-camera.service
```

---

## File Structure

```
sp-cam/
├── camera-fix/                     # Surface Pro 9 camera support files
│   ├── install.sh                  # Main camera installation
│   ├── surface-camera.py           # Camera GUI app
│   ├── 99-surface-cameras.rules    # udev power management rules
│   ├── bin/                        # Helper scripts for GUI app
│   │   ├── camera-prep.sh
│   │   ├── camera-stream.sh
│   │   ├── camera-cleanup.sh
│   │   └── camera-health-check.sh
│   ├── scripts/                    # Test and recovery scripts
│   │   ├── test-front-camera.sh
│   │   ├── test-rear-camera.sh
│   │   └── recovery/
│   │       └── fix-camera-init.sh
│   ├── tests/                      # Camera robustness tests
│   │   ├── README.md
│   │   └── test_robustness.sh
│   └── modules/                    # Prebuilt kernel modules by version
└── howdy-integration/              # Howdy facial recognition integration
    ├── install-howdy-gstreamer.sh  # Howdy GStreamer setup (recommended)
    ├── install-howdy.sh            # Howdy v4l2loopback setup (alternative)
    ├── gstreamer_reader.py         # Howdy GStreamer recorder
    ├── howdy-camera.service        # Systemd service for 24/7 streaming
    └── scripts/howdy/              # Howdy utility scripts
        ├── howdy-camera-stream.sh
        ├── patch-howdy-video-capture.sh
        ├── restart-howdy-stream.sh
        └── setup-howdy-loopback.sh
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

### Camera App Usage Notes

**CRITICAL: Camera Resource Management**
- **DO NOT manually power cycle cameras** via sysfs - let the kernel handle power management
- **Close apps properly** - don't force-kill, as it leaves camera resources locked
- Only one app can access a camera at a time
- Photo capture is disabled (causes resource conflicts)

**Debug Logging:**
All camera operations are logged to `/tmp/surface_camera_debug.log` for troubleshooting.

**Known Camera App Issues:**
1. **Photo capture disabled**: Causes camera resource conflicts - use screenshot tool instead
2. **Camera won't start after crash**: Restart the app or reboot if camera resources are stuck
3. **Inconsistent startup**: Sometimes shows black/grey on first start - switching cameras or restarting fixes it

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

## Surface Pro 9 Linux Setup

Additional changes needed for Surface Pro 9 Linux compatibility.

### 1. Install linux-surface Kernel

The linux-surface project provides kernel patches and drivers specifically for Microsoft Surface devices.

**Repository:** https://github.com/linux-surface/linux-surface

Follow the installation instructions to install the patched kernel and Surface-specific drivers.

### 2. GRUB Configuration Changes

Modify `/etc/default/grub`:

```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash acpi=force acpi_osi=! \"acpi_osi=Windows 2020\""
```

**Parameters explained:**
- `acpi=force` - Forces ACPI support even if the BIOS is dated before 2000
- `acpi_osi=!` - Disables all OS interface strings
- `acpi_osi="Windows 2020"` - Makes the firmware think it's running Windows 2020

These make lid open/close and s2idle sleeping more reliable.

**Update GRUB:**
```bash
sudo update-grub
```

Then reboot for changes to take effect.

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

# Copy to camera-fix/modules/ directory
mkdir -p camera-fix/modules/$(uname -r)
cp drivers/media/i2c/*.ko camera-fix/modules/$(uname -r)/
# etc...
```

## Credits

- Based on [linux-surface PR #1867](https://github.com/linux-surface/linux-surface/pull/1867) by @toorajtaraz
- [linux-surface](https://github.com/linux-surface/linux-surface) project
- Intel IPU6 camera stack

## License

GPL-2.0 (same as Linux kernel)
