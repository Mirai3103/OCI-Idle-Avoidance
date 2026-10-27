## OCI-Idle-Avoidance
A set of scripts designed to maintain a minimum level of CPU usage on Oracle Cloud VMs, preventing them from being reclaimed due to idling. Ideal for environments with fluctuating resource demands.

### Overview
This repository contains scripts to help maintain a minimum level of CPU usage on a virtual machine (VM) to prevent Oracle Cloud Infrastructure (OCI) from shutting it down due to idling. This is in response to a policy change in OCI where VMs can be reclaimed if they idle for a certain period.

The scripts work by monitoring the CPU usage and spinning up "load generator" Python scripts to consume CPU cycles when usage drops below a certain level. If a user's VM is running services that require a lot of resources at times and idles at other times, this script will ensure that the CPU usage stays above the OCI threshold, ensuring the VM remains active even during idle times.

### Structure
This repository contains these scripts: 
1. A Bash script (`load_controller.sh`): This script continuously monitors CPU and memory usage and keeps each around 25%, just above OCI's idle threshold (over 7 days: 95th percentile CPU, network and, on A1 shapes, memory all below 20%). For each resource it starts processes when usage drops below 22%, stops them when usage is above 30%, and stops all of them when usage is above 80%. When your own workload already uses enough CPU or memory, nothing extra runs for it.

2. A Python script (`load_generator.py`): This script keeps a fraction of one core busy, configured by the argument passed to it (e.g. `0.1` = 10%). It runs at the lowest scheduling priority (`nice 19`, `SCHED_IDLE`), so it only ever uses CPU time your real workloads leave idle.

3. A Python script (`mem_holder.py`): This script allocates and holds the given number of megabytes of RAM. It marks itself as the OOM killer's first choice, so your real workloads never get killed because of it.

4. A systemd unit (`oci-idle-avoidance.service`): Runs the controller in the background and starts it again after a reboot.

## Requirements

This script requires:

1. Python 3.x
2. `sysstat` package

The Python 3.x is a requirement for running the `load_generator.py` script that generates load on the CPU.

The `sysstat` package is used to gather system statistics, specifically CPU usage. It includes the `mpstat` command which we use in our shell script to monitor CPU usage.

To install these:

**Python 3.x:**

Python 3 is usually preinstalled in most Linux distributions. If not, you can install it using your system's package manager. For example, on Ubuntu, you can install it via:

```
sudo apt-get install python3
```

**sysstat:**

You can install the `sysstat` package using your system's package manager. For example, on Ubuntu, you can install it via:

```
sudo apt-get install sysstat
```

### How to Use
Install the scripts and the service, then enable it:

```bash
sudo apt-get install sysstat
sudo install -d /opt/oci-idle-avoidance
sudo install -m 755 scripts/load_controller.sh /opt/oci-idle-avoidance/
sudo install -m 644 scripts/load_generator.py /opt/oci-idle-avoidance/
sudo install -m 644 scripts/mem_holder.py /opt/oci-idle-avoidance/
sudo install -m 644 scripts/oci-idle-avoidance.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now oci-idle-avoidance
```

Follow its logs:

```bash
journalctl -u oci-idle-avoidance -f
```

Stop it, and keep it from starting at boot:

```bash
sudo systemctl disable --now oci-idle-avoidance
```

Remove everything (service, unit file, `/opt/oci-idle-avoidance`); add `--remove-sysstat` to also remove `sysstat`:

```bash
./scripts/uninstall.sh
```

To try it in the foreground instead, run `./scripts/load_controller.sh` and stop it with `Ctrl + C`, which also stops all running load generators.

Remember, a busy VM is a happy VM! Happy computing!
