# CLAUDE.md

Keeps an Oracle Cloud Always Free VM from being reclaimed for idling by holding CPU and memory usage around 25%. Oracle counts an instance as idle when, over 7 days, 95th percentile CPU, network and (A1 shapes only) memory are **all** below 20%. See README.md for the user-facing description.

## Layout
- `install.sh` / `uninstall.sh`: run from the repo root by the user. They re-exec themselves through `sudo`, are idempotent, and must stay in sync: the same `SERVICE`, `UNIT_FILE` and `INSTALL_DIR`, and every file `install.sh` places must be removed by `uninstall.sh`.
- `scripts/`: the files that get installed into `/opt/oci-idle-avoidance`.
  - `load_controller.sh`: main loop. `mpstat $INTERVAL 1` measures CPU (it is also the loop's sleep), `/proc/meminfo` `MemAvailable` measures memory. One generic `regulate` function handles both resources, with pid arrays passed by name (bash namerefs, `local -n`).
  - `load_generator.py <fraction of one core>`: busy/sleep duty cycle at `nice 19` + `SCHED_IDLE`.
  - `mem_holder.py <MB>`: fills a bytearray (zeroed allocations are lazily mapped and don't count) and sets `oom_score_adj=1000`.
  - `oci-idle-avoidance.service`: `DynamicUser=yes` (no root needed at runtime), `Restart=always`, `OOMPolicy=continue` (the default `stop` would take down the whole service when the OOM killer picks a memory holder).

## Behavior that must not regress
- Measurements include the controller's own processes, which is intended: Oracle sees the total. When real usage rises above `HIGH`, the controller removes its own processes.
- Check `KILL_ALL` before `HIGH`; the original script had them in the wrong order and the "stop everything" branch was unreachable.
- Keep `export LC_ALL=C`: localized `mpstat` output (e.g. `vi_VN`) breaks the awk parsing.
- Float math goes through awk; `bc` is not a dependency.
- Generators must stay at idle priority so they never compete with real workloads.

## Conventions
- Runtime scripts (`scripts/`) and README are in English. `install.sh` / `uninstall.sh` have detailed comments in Vietnamese, as the user asked.
- Colors in `load_controller.sh` are only emitted on a TTY, so journald logs stay clean.

## Testing
There are no automated tests. Check syntax with `bash -n` on the shell scripts and `python3 -m py_compile` (delete the `__pycache__` it leaves). For real behavior, run `./install.sh` on a VM and watch `journalctl -u oci-idle-avoidance -f` until CPU and memory both settle between 22% and 30%.
