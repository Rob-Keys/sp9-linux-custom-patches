# Howdy Integration for Surface Pro 9 Front Camera

This directory contains the integration between Howdy (facial recognition authentication) and the Surface Pro 9's front camera using libcamera v0.6.0.

## What We've Accomplished

### 1. Custom GStreamer Video Reader
**File**: `gstreamer_reader.py`

Created a custom video recorder that allows Howdy to access the Surface Pro 9 front camera through GStreamer and libcamera v0.6.0.

**Key Features**:
- Opens camera on-demand (no 24/7 streaming required)
- Uses libcamera v0.6.0 from `/usr/local/lib/x86_64-linux-gnu`
- Automatically configures environment variables for newer libcamera
- Rotates video 180° to correct orientation
- Outputs BGR format for OpenCV/dlib compatibility

**How it works**:
- Sets `LD_LIBRARY_PATH` and `GST_PLUGIN_PATH` to use newer libcamera
- Creates GStreamer pipeline: `libcamerasrc → videoflip → videoconvert → appsink`
- Uses default camera (front camera is first in the list)
- Note: Camera name contains backslash (`\_SB_.PC00.I2C3.CAMF`) which causes issues with GStreamer, so we use the default camera instead

### 2. PAM Integration
**File**: `patch-pam-env.sh`

Modified Howdy's PAM module to set the correct library paths when authenticating.

**What it does**:
- Patches `/lib/security/howdy/pam.py` to set environment variables before calling `compare.py`
- Sets `LD_LIBRARY_PATH` to include `/usr/local/lib/x86_64-linux-gnu`
- Sets `GST_PLUGIN_PATH` to include both newer libcamera plugin and system plugins
- Creates backup at `/lib/security/howdy/pam.py.bak`

**Status**: ✅ Installed and patched

### 3. Howdy Configuration
**Configuration**:
- Recording plugin: `gstreamer` (set in `/lib/security/howdy/config.ini`)
- Device path: `/dev/null` (not used, required by Howdy config)
- IR requirement: `false` (Surface Pro 9 camera doesn't have IR)

**Status**: ✅ Configured

### 4. Face Model
**Status**: ✅ Successfully captured face model "Rob"

Face model was captured successfully using:
```bash
sudo LD_LIBRARY_PATH=/usr/local/lib/x86_64-linux-gnu \
     GST_PLUGIN_PATH=/usr/local/lib/x86_64-linux-gnu/gstreamer-1.0:/usr/lib/x86_64-linux-gnu/gstreamer-1.0 \
     howdy add
```

Results:
- Camera opened successfully with libcamera v0.6.0
- Captured 30 frames
- Face model saved to `/lib/security/howdy/models/rob-keys.dat`

## Current Status

### ✅ Working
1. Camera access via GStreamer + libcamera v0.6.0
2. Face model capture with `howdy add`
3. GStreamer reader properly integrated into Howdy
4. PAM module patched with correct environment variables

### ⚠️ Not Working Yet - PAM Authentication
**Issue**: Howdy is not being triggered during `sudo` authentication.

**Missing Dependencies**: Python packages required for face recognition:
- `dlib` - Face recognition library (MISSING)
- `face-recognition` - High-level wrapper (MISSING)
- `opencv-python` - Already installed as `python3-opencv` ✅
- `numpy` - Already installed as `python3-numpy` ✅

**To Fix**:
```bash
sudo pip3 install dlib face-recognition --break-system-packages
```

After installing these dependencies, authentication should work with:
```bash
sudo -k  # Clear cached credentials
sudo ls  # Should trigger Howdy face recognition
```

## Installation Scripts

### Option 1: GStreamer Reader (Recommended)
**File**: `install-howdy-gstreamer.sh`

Installs the on-demand camera access method (no streaming):
```bash
cd ~/Rob/sp-cam/howdy-integration
sudo ./install-howdy-gstreamer.sh
```

**What it does**:
1. Checks and installs Python dependencies
2. Copies `gstreamer_reader.py` to `/usr/lib/security/howdy/recorders/`
3. Patches `video_capture.py` to recognize the gstreamer plugin
4. Updates Howdy config to use gstreamer recorder
5. Stops any running camera streaming services

### Option 2: V4L2 Loopback with 24/7 Streaming
**File**: `install-howdy.sh`

Sets up v4l2loopback device with continuous streaming:
```bash
cd ~/Rob/sp-cam/howdy-integration
sudo ./install-howdy.sh
```

**What it does**:
1. Sets up v4l2loopback device at `/dev/video33`
2. Installs systemd service for camera streaming
3. Configures Howdy to use `/dev/video33`

**Service file**: `howdy-camera.service`
- Streams camera continuously to loopback device
- Path fixed to: `/home/rob-keys/Rob/sp-cam/howdy-integration/scripts/howdy/howdy-camera-stream.sh`

## Technical Details

### Library Paths
The Surface Pro 9 camera requires libcamera v0.6.0, which is installed in `/usr/local`:
- Libraries: `/usr/local/lib/x86_64-linux-gnu/libcamera*.so*`
- GStreamer plugin: `/usr/local/lib/x86_64-linux-gnu/gstreamer-1.0/libgstlibcamera.so`

System has older libcamera v0.2.0 in `/usr/lib`, which doesn't support this camera.

### Camera Information
- **Name**: `\_SB_.PC00.I2C3.CAMF` (Internal front camera)
- **Sensor**: ov5693
- **Resolution**: Tested with 640x480 @ 30fps
- **Orientation**: Requires 180° rotation
- **Note**: Camera name contains backslash-underscore which causes parsing issues in GStreamer

### GStreamer Pipeline
```
libcamerasrc !
video/x-raw,width=640,height=480,framerate=30/1 !
videoflip method=rotate-180 !
videoconvert !
video/x-raw,format=BGR !
appsink name=sink emit-signals=true sync=false max-buffers=1 drop=true
```

### Environment Variables Required
```bash
LD_LIBRARY_PATH=/usr/local/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH
GST_PLUGIN_PATH=/usr/local/lib/x86_64-linux-gnu/gstreamer-1.0:/usr/lib/x86_64-linux-gnu/gstreamer-1.0:$GST_PLUGIN_PATH
```

## Files Modified

### In Howdy Installation
- `/usr/lib/security/howdy/recorders/gstreamer_reader.py` - Custom video reader (NEW)
- `/usr/lib/security/howdy/recorders/video_capture.py` - Patched to support gstreamer plugin
- `/lib/security/howdy/config.ini` - Updated recording_plugin setting
- `/lib/security/howdy/pam.py` - Patched to set environment variables
- `/lib/security/howdy/models/rob-keys.dat` - Face model data (NEW)

### In This Directory
- `gstreamer_reader.py` - Source for custom recorder
- `install-howdy-gstreamer.sh` - Installation script
- `install-howdy.sh` - Alternative installation (v4l2loopback)
- `patch-pam-env.sh` - PAM environment patcher
- `howdy-camera.service` - Systemd service (for v4l2loopback method)
- `howdy-wrapper.sh` - Wrapper script with environment variables
- `scripts/howdy/patch-howdy-video-capture.sh` - Video capture patcher
- `scripts/howdy/howdy-camera-stream.sh` - Camera streaming script
- `scripts/howdy/setup-howdy-loopback.sh` - V4L2 loopback setup
- `scripts/howdy/restart-howdy-stream.sh` - Service restart script

## Next Steps

1. **Install missing Python dependencies**:
   ```bash
   sudo pip3 install dlib face-recognition --break-system-packages
   ```

2. **Test authentication**:
   ```bash
   sudo -k
   sudo ls
   ```
   The camera LED should light up, and Howdy should attempt face recognition.

3. **Add multiple face models** (optional, for different lighting/angles):
   ```bash
   sudo LD_LIBRARY_PATH=/usr/local/lib/x86_64-linux-gnu \
        GST_PLUGIN_PATH=/usr/local/lib/x86_64-linux-gnu/gstreamer-1.0:/usr/lib/x86_64-linux-gnu/gstreamer-1.0 \
        howdy add
   ```
   Give each model a descriptive label like "with_glasses", "evening_light", etc.

4. **Verify PAM integration**:
   ```bash
   grep howdy /etc/pam.d/common-auth
   ```
   Should show: `auth [success=3 default=ignore] pam_python.so /lib/security/howdy/pam.py`

5. **Check logs** if issues occur:
   ```bash
   journalctl -t HOWDY --since "5 minutes ago"
   ```

## Troubleshooting

### Camera LED doesn't light up during sudo
- Check if dlib and face-recognition are installed: `python3 -c "import dlib, face_recognition"`
- Verify PAM patch: `grep "LD_LIBRARY_PATH.*usr/local" /lib/security/howdy/pam.py`
- Check Howdy isn't disabled: `grep disabled /lib/security/howdy/config.ini` (should be `false`)

### Authentication fails / asks for password
- Face recognition may need better lighting
- Try looking straight at camera
- Add additional face models with `howdy add`
- Check certainty threshold in config: `howdy config` and adjust `certainty` value

### Camera not found errors
- Verify environment variables are set in PAM module
- Check libcamera detects camera: `LD_LIBRARY_PATH=/usr/local/lib/x86_64-linux-gnu cam -l`
- Ensure gstreamer_reader.py is in `/usr/lib/security/howdy/recorders/`

### "Recorder doesn't support test command" error
- This is normal - our custom recorder doesn't implement the test UI
- Use actual authentication (`sudo ls`) to test instead

## References
- [Howdy GitHub](https://github.com/boltgolt/howdy)
- [libcamera Documentation](https://libcamera.org/)
- [Surface Pro 9 Camera Integration](../camera-fix/) - Base camera driver setup

## Credits
- Integration developed during debugging session on 2025-12-02
- Uses libcamera v0.6.0 with Surface Pro 9 ov5693 camera
- Based on Howdy v2.6.1
