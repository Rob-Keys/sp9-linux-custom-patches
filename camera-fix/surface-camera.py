#!/usr/bin/python3
"""
Surface Pro 9 Camera App - Combined GUI + Working Logic
GUI from surface-camera.py with the working camera logic from camera_app_simple.py
"""
import gi
import subprocess
import os
import sys
import threading
import time
from datetime import datetime

# CRITICAL: Set environment to use locally built libcamera 0.6.0 instead of system 0.2.0
# The system GStreamer plugin doesn't work with our camera names
os.environ['GST_PLUGIN_PATH'] = '/usr/local/lib/x86_64-linux-gnu/gstreamer-1.0'
os.environ['LD_LIBRARY_PATH'] = '/usr/local/lib/x86_64-linux-gnu:' + os.environ.get('LD_LIBRARY_PATH', '')

gi.require_version('Gtk', '3.0')
gi.require_version('Gst', '1.0')
from gi.repository import Gtk, Gst, GLib, Gdk

Gst.init(None)

class SurfaceCameraApp(Gtk.Window):
    def __init__(self):
        super().__init__(title="Surface Pro 9 Camera")
        self.set_default_size(800, 600)
        self.set_border_width(0)

        # Dark theme preference
        settings = Gtk.Settings.get_default()
        settings.set_property("gtk-application-prefer-dark-theme", True)

        # Camera switching state management
        self.switching_lock = threading.Lock()
        self.is_switching = False
        self.last_switch_time = 0
        self.min_switch_interval = 2.0  # Minimum seconds between switches (optimized for fast switching)
        self.countdown_timer = None  # For button countdown display
        self.original_button_label = None  # Store original label

        # Camera configuration (from camera_app_simple.py)
        # IMPORTANT: Use double backslash so Gst.parse_launch() receives single backslash
        self.cameras = {
            "front": {
                "name": "\\\\_SB_.PC00.I2C3.CAMF",
                "label": "Front Camera (OV5693)",
                "i2c_id": "i2c-OVTI5693:00"
            },
            "rear": {
                "name": "\\\\_SB_.PC00.I2C2.CAMR",
                "label": "Rear Camera (OV13858)",
                "i2c_id": "i2c-OVTID858:00"
            }
        }

        # Photos directory
        self.photos_dir = os.path.expanduser("~/Pictures/SurfaceCamera")
        os.makedirs(self.photos_dir, exist_ok=True)

        # Main Layout
        self.main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.add(self.main_box)

        # Header Bar
        self.header = Gtk.HeaderBar()
        self.header.set_show_close_button(True)
        self.header.set_title("Surface Camera")
        self.set_titlebar(self.header)

        # Switch Camera Button
        self.btn_switch = Gtk.Button(label="Switch to Rear")
        self.btn_switch.connect("clicked", self.on_switch_camera)
        self.header.pack_start(self.btn_switch)

        # Take Photo Button
        self.btn_photo = Gtk.Button(label="Take Photo")
        self.btn_photo.connect("clicked", self.on_take_photo)
        self.header.pack_start(self.btn_photo)

        # Open Folder Button
        self.btn_folder = Gtk.Button(label="Open Photos")
        self.btn_folder.connect("clicked", self.on_open_folder)
        self.header.pack_end(self.btn_folder)

        self.current_camera = "front"

        # Status / Overlay
        self.overlay = Gtk.Overlay()
        self.main_box.pack_start(self.overlay, True, True, 0)

        # Video Area (GtkSink)
        self.video_widget = Gtk.Box()
        self.video_widget.set_size_request(640, 480)
        self.overlay.add(self.video_widget)

        # Loading Spinner / Status Label overlay
        self.status_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.status_box.set_halign(Gtk.Align.CENTER)
        self.status_box.set_valign(Gtk.Align.CENTER)

        self.spinner = Gtk.Spinner()
        self.spinner.set_size_request(32, 32)
        self.status_box.pack_start(self.spinner, True, True, 0)

        self.status_label = Gtk.Label(label="Initializing cameras...")
        self.status_box.pack_start(self.status_label, True, True, 0)

        self.overlay.add_overlay(self.status_box)

        # GStreamer Pipeline
        self.pipeline = None
        self.bus = None
        self.is_streaming = False

        # Debugging log file
        self.log_file = "/tmp/surface_camera_debug.log"
        with open(self.log_file, "w") as f:
            f.write(f"--- SurfaceCameraApp Debug Log - {time.ctime()} ---\n")

        # Signals
        self.connect("destroy", self.on_destroy)

        # Check camera health before starting
        self.check_camera_health()

        # Reset media links to clear any stale state from previous runs
        self.log_message("Resetting media links on startup...")
        try:
            subprocess.run(
                ["media-ctl", "-d", "/dev/media0", "-r"],
                capture_output=True,
                timeout=5
            )
            self.log_message("Initial media link reset successful")
        except Exception as e:
            self.log_message(f"Warning: Failed to reset media links on startup: {e}")

        # Start camera immediately (no prep scripts needed)
        # Use minimal delay - just enough to let GTK initialize
        # Run in background thread to avoid blocking GTK main loop
        GLib.timeout_add(100, lambda: threading.Thread(target=self.start_preview, args=("front",), daemon=True).start())

    def check_camera_health(self):
        """Check camera hardware health at startup"""
        self.log_message("Running camera health check...")
        try:
            health_script = os.path.join(os.path.dirname(__file__), "bin", "camera-health-check.sh")
            if os.path.exists(health_script):
                result = subprocess.run([health_script], capture_output=True, text=True, timeout=5)
                self.log_message(f"Health check output:\n{result.stdout}")
                if result.stderr:
                    self.log_message(f"Health check warnings:\n{result.stderr}")
            else:
                self.log_message(f"Health check script not found at {health_script}")
        except Exception as e:
            self.log_message(f"Health check failed: {e}")

    def log_message(self, message):
        timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
        with open(self.log_file, "a") as f:
            f.write(f"[{timestamp}] {message}\n")
        print(f"DEBUG: {message}")

    def wait_for_camera_ready(self, camera_type, max_wait=10):
        """Poll camera device status until it's ready or timeout"""
        camera = self.cameras[camera_type]
        i2c_id = camera['i2c_id']
        status_path = f"/sys/bus/i2c/devices/{i2c_id}/power/runtime_status"

        if not os.path.exists(status_path):
            self.log_message(f"Camera status path not found: {status_path}, skipping readiness check")
            return True

        self.log_message(f"Waiting for {camera_type} camera to be ready...")
        start_time = time.time()
        poll_interval = 0.1

        while time.time() - start_time < max_wait:
            try:
                with open(status_path, "r") as f:
                    status = f.read().strip()

                if status == "active":
                    elapsed = time.time() - start_time
                    self.log_message(f"Camera ready after {elapsed:.2f}s (status: {status})")
                    return True
                elif status == "suspended":
                    # Camera is suspended, wait for it to wake
                    self.log_message(f"Camera suspended, waiting... ({time.time() - start_time:.1f}s)")
                    time.sleep(poll_interval)
                else:
                    self.log_message(f"Camera status: {status}, waiting...")
                    time.sleep(poll_interval)

            except Exception as e:
                self.log_message(f"Error checking camera status: {e}")
                time.sleep(poll_interval)

        # Timeout reached
        elapsed = time.time() - start_time
        self.log_message(f"Camera readiness timeout after {elapsed:.2f}s")
        return False

    def update_status(self, text, show_spinner=True):
        def _update():
            self.log_message(f"Updating status: {text}")
            self.status_label.set_text(text)
            if show_spinner:
                self.spinner.start()
                self.status_box.show_all()
            else:
                self.spinner.stop()
                self.status_box.hide()
        GLib.idle_add(_update)

    def start_preview(self, camera_type):
        self.log_message(f"Entering start_preview for camera: {camera_type}")

        # Acquire lock to prevent concurrent camera operations
        if not self.switching_lock.acquire(blocking=False):
            self.log_message("Camera switch already in progress, ignoring request")
            self.update_status("Please wait, camera is switching...", show_spinner=False)
            GLib.timeout_add(2000, self.update_status, "", False)
            return False

        try:
            self.is_switching = True
            previous_camera = self.current_camera if self.pipeline else None

            # Stop existing pipeline if any
            if self.pipeline:
                self.log_message("Stopping existing pipeline.")
                self.is_streaming = False
                try:
                    # Stop pipeline - go directly to NULL for faster, cleaner shutdown
                    self.pipeline.set_state(Gst.State.NULL)
                    # Wait for pipeline to fully stop with timeout
                    state_return = self.pipeline.get_state(10 * Gst.SECOND)
                    if state_return[0] == Gst.StateChangeReturn.FAILURE:
                        self.log_message("Pipeline failed to stop cleanly, forcing cleanup")
                    else:
                        self.log_message(f"Pipeline stopped successfully (state: {state_return[1]})")
                except Exception as e:
                    self.log_message(f"Error stopping pipeline: {e}")

                # CRITICAL: Clean up bus before deleting pipeline
                # Remove signal watch to prevent memory leaks
                if self.bus:
                    try:
                        self.bus.remove_signal_watch()
                        self.log_message("Bus signal watch removed")
                    except:
                        pass
                    self.bus = None

                # CRITICAL: Unref and delete pipeline to fully release camera
                # This ensures libcamera releases the media device
                self.pipeline = None

                # Force garbage collection to ensure GStreamer elements are cleaned up
                import gc
                gc.collect()
                self.log_message("Pipeline deleted and garbage collected")

                # Give the camera hardware time to fully release
                # Different cameras need different settle times
                if previous_camera:
                    # Front camera (OV5693) is slower to release - needs more time
                    # Rear camera (OV13858) releases faster
                    if previous_camera == "front":
                        settle_time = 1.0  # Front camera needs more settle time
                    else:
                        settle_time = 0.5  # Rear camera releases faster

                    self.log_message(f"Waiting {settle_time}s for {previous_camera} camera to release...")
                    time.sleep(settle_time)

            self.update_status(f"🎥 Starting {camera_type} camera preview...", show_spinner=True)

            camera = self.cameras[camera_type]
            camera_name = camera['name']
            self.log_message(f"Using camera: {camera_name} ({camera['label']})")

            # IMPORTANT: Camera only wakes from suspended state when GStreamer accesses it
            # Don't check readiness before starting - it will always be suspended
            # The kernel's runtime PM will wake it automatically when accessed
            # Media links are IMMUTABLE and managed by libcamera - don't try to change them manually

            # Poke the camera's power state to help it wake up faster
            try:
                i2c_path = f"/sys/bus/i2c/devices/{camera['i2c_id']}/power/control"
                if os.path.exists(i2c_path):
                    with open(i2c_path, 'r') as f:
                        current = f.read().strip()
                    self.log_message(f"Camera power control: {current}")
                    # Don't change it, just reading helps wake it up
            except Exception as e:
                self.log_message(f"Could not check camera power state: {e}")

            # Try to start the pipeline with retries
            max_retries = 2
            retry_delay = 2.0

            for attempt in range(max_retries + 1):
                try:
                    if attempt > 0:
                        self.log_message(f"Retry attempt {attempt}/{max_retries} after {retry_delay}s delay...")
                        self.update_status(f"⚠️ Retrying camera start... (attempt {attempt}/{max_retries})", show_spinner=True)
                        time.sleep(retry_delay)
                        retry_delay *= 1.5  # Exponential backoff

                    # Create simple pipeline - just preview, no photo capture
                    # libcamerasrc -> queue -> caps -> videoflip -> videoconvert -> gtksink
                    # IMPORTANT: camera-name must be quoted because it contains backslashes
                    cmd = (f'libcamerasrc camera-name="{camera_name}" ! '
                           "queue max-size-buffers=3 leaky=downstream ! "
                           "video/x-raw,width=1280,height=720 ! "
                           "videoflip method=rotate-180 ! "
                           "videoconvert ! "
                           "gtksink name=sink sync=false")
                    self.log_message(f"GStreamer pipeline command: {cmd}")

                    self.pipeline = Gst.parse_launch(cmd)
                    self.log_message("GStreamer pipeline launched.")

                    # Set up bus to monitor for errors - BEFORE doing anything else
                    self.bus = self.pipeline.get_bus()
                    self.bus.add_signal_watch()
                    error_msg = None

                    def bus_error_callback(bus, message):
                        nonlocal error_msg
                        if message.type == Gst.MessageType.ERROR:
                            err, debug = message.parse_error()
                            error_msg = f"{err}: {debug}"
                            self.log_message(f"BUS ERROR: {error_msg}")

                    self.bus.connect("message::error", bus_error_callback)

                    # Get sink and connect to widget
                    sink = self.pipeline.get_by_name("sink")
                    widget = sink.get_property("widget")

                    # Replace existing video widget content
                    for child in self.video_widget.get_children():
                        self.video_widget.remove(child)
                    self.video_widget.add(widget)
                    self.video_widget.show_all()
                    self.log_message("Video widget updated and shown.")

                    # Start playing
                    self.log_message("Setting pipeline to PLAYING state...")
                    ret = self.pipeline.set_state(Gst.State.PLAYING)
                    self.log_message(f"set_state returned: {ret}")

                    if ret == Gst.StateChangeReturn.FAILURE:
                        # Process any pending bus messages to get error details
                        time.sleep(0.1)
                        while self.bus.have_pending():
                            msg = self.bus.pop()
                            if msg and msg.type == Gst.MessageType.ERROR:
                                err, debug = msg.parse_error()
                                error_msg = f"{err}: {debug}"
                                self.log_message(f"Error from bus: {error_msg}")

                        if error_msg:
                            raise Exception(f"Pipeline error: {error_msg}")
                        else:
                            raise Exception("Unable to set pipeline to playing (no error details)")

                    # Wait for pipeline to reach PLAYING state with active bus message processing
                    # This is CRITICAL for async state transitions - we must pump messages
                    self.log_message("Waiting for pipeline to reach PLAYING state...")

                    timeout_ns = 20 * Gst.SECOND  # 20 second timeout (cameras can be slow to wake)
                    start_time = time.time()
                    state_reached = False
                    last_log_time = start_time

                    while (time.time() - start_time) * Gst.SECOND < timeout_ns:
                        # Actively pump bus messages - this is essential for state transitions
                        msg = self.bus.timed_pop_filtered(
                            100 * Gst.MSECOND,  # Poll every 100ms
                            Gst.MessageType.ERROR | Gst.MessageType.ASYNC_DONE | Gst.MessageType.STATE_CHANGED
                        )

                        if msg:
                            if msg.type == Gst.MessageType.ERROR:
                                err, debug = msg.parse_error()
                                error_msg = f"{err}: {debug}"
                                self.log_message(f"ERROR during state change: {error_msg}")
                                break
                            elif msg.type == Gst.MessageType.ASYNC_DONE:
                                self.log_message("Received ASYNC_DONE message")
                            elif msg.type == Gst.MessageType.STATE_CHANGED:
                                if msg.src == self.pipeline:
                                    old, new, pending = msg.parse_state_changed()
                                    self.log_message(f"Pipeline state: {old} -> {new} (pending: {pending})")

                        # Check current state
                        ret, current, pending = self.pipeline.get_state(0)  # Non-blocking check

                        if current == Gst.State.PLAYING and pending == Gst.State.VOID_PENDING:
                            self.log_message(f"Pipeline reached PLAYING state after {time.time() - start_time:.2f}s")
                            state_reached = True
                            break
                        elif ret == Gst.StateChangeReturn.FAILURE:
                            raise Exception("Pipeline state change failed")

                        # Log progress every 2 seconds if stuck
                        if time.time() - last_log_time > 2.0:
                            elapsed = time.time() - start_time
                            self.log_message(f"Still waiting for PLAYING state... (current: {current}, pending: {pending}, elapsed: {elapsed:.1f}s)")
                            last_log_time = time.time()

                    # Connect to ongoing bus message handler (signal watch already added above)
                    self.bus.connect("message", self.on_bus_message)

                    # Check final status
                    if error_msg:
                        raise Exception(f"GStreamer error: {error_msg}")

                    if not state_reached:
                        # Do one final blocking check with longer timeout
                        ret, current, pending = self.pipeline.get_state(5 * Gst.SECOND)
                        if current != Gst.State.PLAYING:
                            # PAUSED state is actually okay - it means pipeline is ready and prerolled
                            # The camera will transition to PLAYING once frames start flowing
                            # This is normal behavior for live sources that are slow to start
                            if current == Gst.State.PAUSED and pending == Gst.State.VOID_PENDING:
                                self.log_message(f"Pipeline in PAUSED state (prerolled), will transition to PLAYING automatically")
                                state_reached = True
                            else:
                                # Only fail if we're not in a reasonable state
                                self.log_message(f"Pipeline in unexpected state, attempting recovery...")
                                if current == Gst.State.PAUSED:
                                    self.pipeline.set_state(Gst.State.NULL)
                                    time.sleep(0.5)
                                raise Exception(f"Pipeline stuck in {current} state (pending: {pending}), expected PLAYING")
                        else:
                            self.log_message(f"Pipeline reached PLAYING after final check")

                    self.log_message("GStreamer pipeline set to PLAYING.")

                    self.update_status("", show_spinner=False)
                    self.is_streaming = True
                    self.log_message("Streaming started, overlay hidden.")

                    # Update Button Text
                    if camera_type == "front":
                        self.btn_switch.set_label("Switch to Rear")
                        self.current_camera = "front"
                    else:
                        self.btn_switch.set_label("Switch to Front")
                        self.current_camera = "rear"
                    self.log_message(f"Switch button label updated to: {self.btn_switch.get_label()}")

                    break  # Success! Exit retry loop

                except Exception as e:
                    self.log_message(f"Exception during start_preview (attempt {attempt}): {e}")

                    # Clean up failed pipeline
                    if self.pipeline:
                        try:
                            self.pipeline.set_state(Gst.State.NULL)
                            self.pipeline.get_state(5 * Gst.SECOND)  # Wait for cleanup
                        except:
                            pass
                    if self.bus:
                        try:
                            self.bus.remove_signal_watch()
                        except:
                            pass
                        self.bus = None
                    self.pipeline = None

                    # If this was the last attempt, show error
                    if attempt >= max_retries:
                        self.update_status(f"❌ Camera failed to start after {max_retries} retries. Try restarting the app.", show_spinner=False)
                        GLib.idle_add(lambda: self.btn_switch.set_sensitive(False))

        finally:
            # Always release the lock and update state
            self.is_switching = False
            self.last_switch_time = time.time()
            self.switching_lock.release()
            # Start countdown timer on button
            GLib.idle_add(self.start_countdown_timer)
            self.log_message("Camera switch completed, lock released, countdown started")

        return False  # Don't repeat timeout

    def on_bus_message(self, bus, message):
        """Handle GStreamer bus messages"""
        t = message.type
        if t == Gst.MessageType.ERROR:
            err, debug = message.parse_error()
            self.log_message(f"GStreamer Error: {err}, {debug}")

            # Stop the broken pipeline
            if self.pipeline:
                try:
                    self.pipeline.set_state(Gst.State.NULL)
                except:
                    pass
                self.pipeline = None

            self.is_streaming = False
            self.update_status(f"Camera Error - Hardware may need reset. Please restart the app.", show_spinner=False)

            # Disable switch button to prevent further issues
            GLib.idle_add(lambda: self.btn_switch.set_sensitive(False))

        elif t == Gst.MessageType.WARNING:
            err, debug = message.parse_warning()
            self.log_message(f"GStreamer Warning: {err}, {debug}")
        elif t == Gst.MessageType.EOS:
            self.log_message("End of stream")
            self.is_streaming = False
        return True

    def update_countdown_timer(self):
        """Update button with countdown timer"""
        time_since_last_switch = time.time() - self.last_switch_time
        if time_since_last_switch < self.min_switch_interval:
            remaining = int(self.min_switch_interval - time_since_last_switch) + 1
            self.btn_switch.set_label(f"⏳ Wait {remaining}s")
            self.btn_switch.set_sensitive(False)
            return True  # Continue timer
        else:
            # Re-enable button with proper label
            if self.current_camera == "front":
                self.btn_switch.set_label("Switch to Rear")
            else:
                self.btn_switch.set_label("Switch to Front")
            self.btn_switch.set_sensitive(True)
            self.countdown_timer = None
            return False  # Stop timer

    def start_countdown_timer(self):
        """Start the countdown timer on the button"""
        if self.countdown_timer is None:
            self.countdown_timer = GLib.timeout_add(100, self.update_countdown_timer)

    def on_switch_camera(self, widget):
        # Check if we're already switching
        if self.is_switching:
            self.log_message("Camera switch ignored - already in progress")
            return

        # Check minimum time between switches (debouncing)
        time_since_last_switch = time.time() - self.last_switch_time
        if time_since_last_switch < self.min_switch_interval:
            remaining = self.min_switch_interval - time_since_last_switch
            self.log_message(f"Camera switch too fast - {remaining:.1f}s remaining")
            # Start countdown on button if not already running
            self.start_countdown_timer()
            return

        # Disable switch button during transition
        self.btn_switch.set_sensitive(False)
        self.btn_switch.set_label("🔄 Switching...")

        new_cam = "rear" if self.current_camera == "front" else "front"
        self.log_message(f"Initiating camera switch from {self.current_camera} to {new_cam}")

        # Run camera switch in background thread to keep UI responsive
        threading.Thread(target=self.start_preview, args=(new_cam,), daemon=True).start()

    def on_take_photo(self, widget):
        """Photo capture disabled - causes camera conflicts"""
        self.update_status("Photo capture disabled (causes camera issues)", show_spinner=False)
        GLib.timeout_add(2000, self.update_status, "", False)
        self.log_message("Photo capture attempted but disabled")

    def on_open_folder(self, widget):
        """Open photos folder"""
        try:
            subprocess.Popen(["xdg-open", self.photos_dir],
                           stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL)
            self.log_message(f"Opening photos folder: {self.photos_dir}")
            self.update_status("Opening photos folder...", show_spinner=False)
            GLib.timeout_add(2000, self.update_status, "", False)
        except Exception as e:
            self.log_message(f"Could not open folder: {e}")
            self.update_status(f"Could not open folder: {e}", show_spinner=False)
            GLib.timeout_add(2000, self.update_status, "", False)

    def on_destroy(self, widget):
        self.log_message("Application closing...")

        # Clean up GStreamer resources properly
        if self.pipeline:
            try:
                # Stop the pipeline and wait for it to fully stop
                self.log_message("Stopping pipeline...")
                self.pipeline.set_state(Gst.State.NULL)
                ret, state, pending = self.pipeline.get_state(5 * Gst.SECOND)
                if ret == Gst.StateChangeReturn.SUCCESS:
                    self.log_message("Pipeline stopped successfully")
                else:
                    self.log_message(f"Pipeline stop returned: {ret}")
            except Exception as e:
                self.log_message(f"Error stopping pipeline on exit: {e}")

        # Remove bus signal watch to prevent memory leaks
        if self.bus:
            try:
                self.bus.remove_signal_watch()
                self.log_message("Bus signal watch removed on exit")
            except Exception as e:
                self.log_message(f"Error removing bus watch: {e}")
            self.bus = None

        # Clear pipeline reference
        self.pipeline = None

        # Force garbage collection before exit
        import gc
        gc.collect()
        self.log_message("Resources cleaned up, exiting...")

        Gtk.main_quit()

if __name__ == "__main__":
    app = SurfaceCameraApp()
    app.show_all()
    Gtk.main()
