## OCI-Idle-Avoidance
Keeps an Oracle Cloud Always Free VM from being reclaimed for idling, by holding CPU and memory usage just above Oracle's idle threshold, and only when your own workload doesn't already.

### Why
Oracle reclaims idle Always Free compute instances. An instance counts as idle when, over a 7-day period, **all** of these are true:

- CPU utilization at the 95th percentile is below 20%
- Network utilization is below 20%
- Memory utilization is below 20% (A1 shapes only)

This project keeps both CPU and memory around **25%**, so the instance never meets that definition, even during weeks where you don't use it.

> Tip: Always Free resources on a **Pay As You Go** account are not reclaimed. If you can upgrade (you are still not billed while staying within the free limits), you don't need this at all.

### How it works
A controller runs as a systemd service and measures usage every 10 seconds. CPU and memory are each regulated with the same thresholds:

| Total usage | Action |
|---|---|
| below 22% | start enough processes to reach about 25% |
| 22% – 30% | do nothing |
| above 30% | stop enough processes to come back to about 25% |
| above 80% | stop all of them |

Usage is measured for the whole VM, including the controller's own processes. So when your real workload already uses more than 30%, everything the controller started is stopped, and it stays out of the way until usage drops again.

- **CPU:** each load generator keeps 10% of one core busy (5% of total on a 2-core VM). It runs at the lowest scheduling priority (`nice 19`, `SCHED_IDLE`), so it only uses CPU time your real workloads leave idle.
- **Memory:** each memory holder allocates and fills 5% of total RAM (about 600 MB on a 12 GB VM). Usage is measured from `MemAvailable`, so page cache doesn't count. Each holder sets `oom_score_adj=1000`, so if your workload suddenly needs RAM faster than the controller reacts, the kernel kills a holder first, never your workload. The service uses `OOMPolicy=continue`, so that doesn't stop the controller.

### Requirements
- A Linux VM running systemd (tested on Ubuntu 24.04, aarch64 A1 shape)
- `sudo` access
- `python3` and `sysstat` (for `mpstat`); `install.sh` installs them with apt, dnf or yum when missing

### Install
```bash
git clone <this repo> OCI-Idle-Avoidance
cd OCI-Idle-Avoidance
./install.sh
```

This installs the scripts into `/opt/oci-idle-avoidance`, installs and starts the `oci-idle-avoidance` systemd service (it also starts at boot), and puts a copy of the uninstaller at `~/uninstall-oci-idle-avoidance.sh`.

To update, `git pull` and run `./install.sh` again. It overwrites the installed files and restarts the service.

### Check that it's working
```bash
systemctl status oci-idle-avoidance
journalctl -u oci-idle-avoidance -f
```

A healthy log settles around 25% for both:

```
Target 25% CPU on 2 cores: 5% per load generator, max 6
Target 25% memory of 11927 MB: 596 MB per memory holder, max 6
Average CPU Usage: 27.3%. Current number of CPU processes: 5
Average Memory Usage: 25.2%. Current number of Memory processes: 3
```

### Configure
The thresholds are at the top of `scripts/load_controller.sh` (`TARGET`, `LOW`, `HIGH`, `KILL_ALL`, `CPU_STEP`, `MEM_STEP`, `INTERVAL`). Edit them, then run `./install.sh` again.

### Stop or uninstall
Pause it, and keep it from starting at boot:

```bash
sudo systemctl disable --now oci-idle-avoidance
```

Remove everything (service, unit file, `/opt/oci-idle-avoidance`, the uninstaller copy in `~`):

```bash
./uninstall.sh                    # keeps sysstat
./uninstall.sh --remove-sysstat   # also removes sysstat
```

If you already deleted the repo, run `~/uninstall-oci-idle-avoidance.sh` instead.

### Repository layout
| Path | Purpose |
|---|---|
| `install.sh` | Installs dependencies, scripts and the service |
| `uninstall.sh` | Reverses everything `install.sh` did |
| `scripts/load_controller.sh` | Measures CPU and memory and starts/stops the processes below |
| `scripts/load_generator.py` | Keeps a fraction of one core busy at idle priority |
| `scripts/mem_holder.py` | Allocates and holds a given amount of RAM |
| `scripts/oci-idle-avoidance.service` | systemd unit that runs the controller |

To try the controller in the foreground without installing it, run `./scripts/load_controller.sh` (needs `sysstat`) and stop it with `Ctrl + C`, which also stops everything it started.
