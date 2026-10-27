import os
import sys
import time

# Fraction of one core to keep busy, e.g. 0.1 = 10%
usage = float(sys.argv[1])
if not 0 < usage <= 1:
    sys.exit("usage must be in (0, 1]")

period = 0.1  # length of one busy + sleep cycle, in seconds
busy_time = usage * period
sleep_time = period - busy_time

# Lowest priority, so real workloads always get the CPU first
os.nice(19)
try:
    os.sched_setscheduler(0, os.SCHED_IDLE, os.sched_param(0))
except (AttributeError, OSError):
    pass

while True:
    start_time = time.monotonic()

    # Use CPU for the specified amount of time
    while time.monotonic() - start_time < busy_time:
        pass

    # Sleep for the rest of the cycle
    time.sleep(sleep_time)
