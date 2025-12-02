#!/bin/bash
# Test camera app robustness across multiple start/stop cycles

NUM_CYCLES=${1:-5}
echo "Testing camera app robustness over $NUM_CYCLES cycles..."

for i in $(seq 1 $NUM_CYCLES); do
  echo "=== Session $i/$NUM_CYCLES ==="
  /usr/bin/python3 /home/rob-keys/Rob/sp-cam/surface-camera.py &
  APP_PID=$!
  sleep 3
  kill -TERM $APP_PID 2>/dev/null
  wait $APP_PID 2>/dev/null
  EXIT_CODE=$?
  if [ $EXIT_CODE -ne 0 ] && [ $EXIT_CODE -ne 143 ] && [ $EXIT_CODE -ne 130 ]; then
    echo "ERROR: Session $i exited with code $EXIT_CODE"
    exit 1
  fi
  echo "Session $i: OK"
  sleep 2
done

echo ""
echo "✓ All $NUM_CYCLES cycles completed successfully"
echo ""
echo "Recent log entries:"
tail -20 /tmp/surface_camera_debug.log
