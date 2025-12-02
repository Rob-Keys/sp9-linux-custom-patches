#!/bin/bash
# Wrapper script to run Howdy with the correct libcamera v0.6.0

# Set library paths to use the newer libcamera
export LD_LIBRARY_PATH="/usr/local/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}"
export GST_PLUGIN_PATH="/usr/local/lib/x86_64-linux-gnu/gstreamer-1.0:${GST_PLUGIN_PATH}"
export GST_PLUGIN_SYSTEM_PATH="/usr/local/lib/x86_64-linux-gnu/gstreamer-1.0"

# Run the actual howdy command
exec /usr/local/bin/howdy "$@"
