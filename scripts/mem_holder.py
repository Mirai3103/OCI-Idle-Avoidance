import sys
import time

# Megabytes of RAM to hold
size_mb = int(sys.argv[1])
if size_mb <= 0:
    sys.exit("size must be a positive number of megabytes")

# Be the first process the OOM killer picks, so real workloads never die for this
try:
    with open("/proc/self/oom_score_adj", "w") as f:
        f.write("1000")
except OSError:
    pass

# Fill every byte so the kernel really backs it with RAM
# (a zeroed allocation stays lazily mapped and does not count as used)
block = bytearray(b"\x01") * (size_mb * 1024 * 1024)

# Hold it until killed
while True:
    time.sleep(3600)
