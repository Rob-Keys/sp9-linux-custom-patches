#!/bin/bash
# Patch Howdy's PAM module to set correct library paths

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root: sudo ./patch-pam-env.sh"
  exit 1
fi

PAM_FILE="/lib/security/howdy/pam.py"

# Check if already patched
if grep -q "LD_LIBRARY_PATH.*usr/local" "$PAM_FILE"; then
    echo "Already patched!"
    exit 0
fi

# Backup original
cp "$PAM_FILE" "$PAM_FILE.bak"

# Add environment variable setup before the subprocess.call line
# We'll insert right after line 42 (the blank line after syslog)
sed -i '43 a\
\	# Set environment for newer libcamera\
\	env = os.environ.copy()\
\	env["LD_LIBRARY_PATH"] = "/usr/local/lib/x86_64-linux-gnu:" + env.get("LD_LIBRARY_PATH", "")\
\	env["GST_PLUGIN_PATH"] = "/usr/local/lib/x86_64-linux-gnu/gstreamer-1.0:/usr/lib/x86_64-linux-gnu/gstreamer-1.0:" + env.get("GST_PLUGIN_PATH", "")\
' "$PAM_FILE"

# Now update the subprocess.call to use the modified environment
sed -i 's/status = subprocess.call(\[/status = subprocess.call([/' "$PAM_FILE"
sed -i '/status = subprocess.call/s/)$/, env=env)/' "$PAM_FILE"

echo "Patched successfully!"
echo "Backup saved to: $PAM_FILE.bak"
echo ""
echo "You can now test with: sudo ls"
