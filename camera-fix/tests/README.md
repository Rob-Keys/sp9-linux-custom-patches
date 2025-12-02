# Surface Camera Tests

## test_robustness.sh

Tests the camera app's ability to handle multiple start/stop cycles without crashes or resource leaks.

Usage:
```bash
./tests/test_robustness.sh [num_cycles]
```

Default is 5 cycles. Each cycle:
1. Starts the camera app
2. Waits 3 seconds for initialization
3. Cleanly terminates the app
4. Waits 2 seconds for cleanup
5. Checks for clean exit (no segfaults)

Example:
```bash
# Test with 10 cycles
./tests/test_robustness.sh 10
```
