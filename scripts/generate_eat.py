#!/usr/bin/env python3
"""
generate_eat.py

Derives Effective Access Time (EAT) CSVs from each trace's per-size hit-rate
CSVs in simulator/build/reports/{trace}/csv/:

    EAT = hit_rate * CACHE_LATENCY_MS + miss_rate * backend_latency_ms

Two backend instances are computed per trace/sample, using the constants
below (edit these to try different latencies):

    {trace}_sample{N}_eat_fast.csv   — backend latency = FAST_BACKEND_LATENCY_MS
    {trace}_sample{N}_eat_slow.csv   — backend latency = SLOW_BACKEND_LATENCY_MS

Run from the Caffeine project root:
    python scripts/generate_eat.py
"""
import csv
import re
from collections import defaultdict
from pathlib import Path

REPORTS_DIR = Path(__file__).parent.parent / "simulator" / "build" / "reports"
SKIP_DIRS   = {"simulate"}
SKIP_SUFFIX = "_old"

# ── Latency configuration (ms) — edit these to model different hardware ─────
CACHE_LATENCY_MS         = 0.2
FAST_BACKEND_LATENCY_MS  = 200
SLOW_BACKEND_LATENCY_MS  = 800

BACKENDS = {
    "fast": FAST_BACKEND_LATENCY_MS,
    "slow": SLOW_BACKEND_LATENCY_MS,
}

_SIZE_RE = re.compile(r"^(.+)_sample(\d+)_size(\d+)\.csv$")


def main() -> None:
    if not REPORTS_DIR.exists():
        print(f"[ERROR] Reports directory not found:\n  {REPORTS_DIR}")
        return

    total = 0

    for trace_dir in sorted(REPORTS_DIR.iterdir()):
        if not trace_dir.is_dir():
            continue
        if trace_dir.name in SKIP_DIRS or trace_dir.name.endswith(SKIP_SUFFIX):
            continue

        csv_dir = trace_dir / "csv"

        # Group per-size CSVs by (trace_name, sample_number)
        groups: dict[tuple[str, int], list[tuple[int, Path]]] = defaultdict(list)
        for csv_path in sorted(csv_dir.glob("*.csv")):
            m = _SIZE_RE.match(csv_path.name)
            if m:
                key = (m.group(1), int(m.group(2)))
                groups[key].append((int(m.group(3)), csv_path))

        if not groups:
            continue

        for (trace_name, sample_n), size_files in sorted(groups.items()):
            size_files.sort(key=lambda t: t[0])

            sizes = []
            # backend -> policy -> list of EAT values (one per cache size, in order)
            backend_policy_rows: dict[str, dict[str, list[float]]] = {
                backend: {} for backend in BACKENDS
            }

            for cache_size, csv_path in size_files:
                sizes.append(cache_size)
                with csv_path.open(newline="") as fh:
                    reader = csv.DictReader(fh)
                    for row in reader:
                        policy    = row["Policy"]
                        hit_rate  = float(row["Hit Rate"]) / 100.0
                        miss_rate = float(row["Miss Rate"]) / 100.0
                        for backend, backend_latency_ms in BACKENDS.items():
                            eat = hit_rate * CACHE_LATENCY_MS + miss_rate * backend_latency_ms
                            backend_policy_rows[backend].setdefault(policy, []).append(eat)

            for backend in BACKENDS:
                out_path = csv_dir / f"{trace_name}_sample{sample_n}_eat_{backend}.csv"
                with out_path.open("w", newline="") as fh:
                    writer = csv.writer(fh)
                    writer.writerow(["Policy"] + [f"{s:,}" for s in sizes])
                    for policy, values in backend_policy_rows[backend].items():
                        writer.writerow([policy] + [f"{v:.4f}" for v in values])

                print(f"  OK  {out_path.name}")
                total += 1

    print(f"\nDone. {total} EAT CSVs generated.")


if __name__ == "__main__":
    main()
