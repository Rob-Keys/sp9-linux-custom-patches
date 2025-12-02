"""
GStreamer video recorder for Howdy
Allows Howdy to directly access libcamera-based cameras on-demand
"""

import os
import sys

# Ensure we use the newer libcamera installation
# CRITICAL: Set these BEFORE importing GStreamer
os.environ['LD_LIBRARY_PATH'] = '/usr/local/lib/x86_64-linux-gnu:' + os.environ.get('LD_LIBRARY_PATH', '')
# Include both the newer libcamera plugin and the system plugins
os.environ['GST_PLUGIN_PATH'] = '/usr/local/lib/x86_64-linux-gnu/gstreamer-1.0:/usr/lib/x86_64-linux-gnu/gstreamer-1.0:' + os.environ.get('GST_PLUGIN_PATH', '')

import gi
gi.require_version('Gst', '1.0')
from gi.repository import Gst
import numpy as np


class gstreamer_reader:
    """
    GStreamer-based video capture for libcamera cameras.
    Opens the camera only when Howdy needs it, closes when done.
    """

    def __init__(self, device_path, camera_name='\\_SB_.PC00.I2C3.CAMF'):
        """
        Initialize GStreamer pipeline for libcamera

        Args:
            device_path: Not used (kept for compatibility with Howdy)
            camera_name: The libcamera camera name (ACPI path)
        """
        # Initialize GStreamer
        Gst.init(None)

        self.camera_name = camera_name
        self.width = 640
        self.height = 480
        self.pipeline = None
        self.appsink = None
        self.bus = None

        # Build the pipeline
        self._create_pipeline()

    def _create_pipeline(self):
        """Create the GStreamer pipeline"""
        # Pipeline: libcamera source -> videoflip -> convert -> appsink
        # Note: Using default camera (first one) as camera-name with backslash causes issues
        pipeline_str = (
            f"libcamerasrc ! "
            f"video/x-raw,width={self.width},height={self.height},framerate=30/1 ! "
            f"videoflip method=rotate-180 ! "
            f"videoconvert ! "
            f"video/x-raw,format=BGR ! "
            f"appsink name=sink emit-signals=true sync=false max-buffers=1 drop=true"
        )

        try:
            print(f"[DEBUG] Creating pipeline with camera: {self.camera_name}")
            print(f"[DEBUG] Pipeline string: {pipeline_str}")
            self.pipeline = Gst.parse_launch(pipeline_str)
            self.appsink = self.pipeline.get_by_name('sink')
            self.bus = self.pipeline.get_bus()
            self.bus.add_signal_watch()

            # Start the pipeline
            print("[DEBUG] Starting pipeline...")
            ret = self.pipeline.set_state(Gst.State.PLAYING)
            print(f"[DEBUG] set_state returned: {ret}")

            if ret == Gst.StateChangeReturn.FAILURE:
                # Check for error messages immediately
                msg = self.bus.pop_filtered(Gst.MessageType.ERROR)
                if msg:
                    err, debug = msg.parse_error()
                    print(f"[ERROR] GStreamer error: {err.message}")
                    print(f"[DEBUG] {debug}")
                    raise RuntimeError(f"GStreamer error: {err.message}")
                else:
                    print("[ERROR] Failed to start pipeline - no error message available")
                    raise RuntimeError("Failed to start GStreamer pipeline")

            # Wait for pipeline to be ready (with timeout)
            print("[DEBUG] Waiting for pipeline to be ready...")
            msg = self.bus.timed_pop_filtered(
                5 * Gst.SECOND,  # 5 second timeout
                Gst.MessageType.ASYNC_DONE | Gst.MessageType.ERROR
            )

            if msg:
                if msg.type == Gst.MessageType.ERROR:
                    err, debug = msg.parse_error()
                    print(f"[ERROR] GStreamer error: {err.message}")
                    print(f"[DEBUG] {debug}")
                    raise RuntimeError(f"GStreamer error: {err.message}")
                print("[DEBUG] Pipeline ready!")
            else:
                print("[WARNING] Pipeline ready timeout - continuing anyway")

        except Exception as e:
            print(f"Failed to create GStreamer pipeline: {e}")
            raise

    def read(self):
        """
        Read a frame from the camera

        Returns:
            (success, frame): Tuple of success boolean and BGR numpy array
        """
        if not self.pipeline:
            return False, None

        # Pull a sample from the appsink
        sample = self.appsink.emit('pull-sample')
        if not sample:
            return False, None

        # Get the buffer and caps from the sample
        buffer = sample.get_buffer()
        caps = sample.get_caps()

        # Extract frame dimensions from caps
        structure = caps.get_structure(0)
        width = structure.get_value('width')
        height = structure.get_value('height')

        # Map the buffer to numpy array
        success, map_info = buffer.map(Gst.MapFlags.READ)
        if not success:
            return False, None

        # Create numpy array from buffer data
        frame = np.ndarray(
            shape=(height, width, 3),
            dtype=np.uint8,
            buffer=map_info.data
        )

        # Unmap the buffer
        buffer.unmap(map_info)

        return True, frame

    def grab(self):
        """
        Grab a frame (compatibility method for OpenCV API)
        Returns True if successful
        """
        if not self.pipeline:
            return False

        # Just check if pipeline is playing
        state = self.pipeline.get_state(0)
        return state[1] == Gst.State.PLAYING

    def set(self, prop_id, value):
        """
        Set a property (compatibility method for OpenCV API)
        This is mostly a no-op for our purposes
        """
        # CAP_PROP_FRAME_WIDTH and CAP_PROP_FRAME_HEIGHT could be handled
        # but we use fixed 640x480 for Howdy
        pass

    def release(self):
        """Release the camera and cleanup resources"""
        if self.pipeline:
            self.pipeline.set_state(Gst.State.NULL)
            self.pipeline = None
            self.appsink = None
            self.bus = None

    def __del__(self):
        """Cleanup on deletion"""
        self.release()
