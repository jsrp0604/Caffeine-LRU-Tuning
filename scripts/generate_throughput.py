#!/usr/bin/env python3
import csv
import re
from collections import defaultdict
from pathlib import Path

REPORTS_DIR = Path(__file__).parent.parent / "simulator" / "build" / "reports"
SKIP_DIRS   = {"simulate"}
SKIP_SUFFIX = "_old"

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

            sizes    = []
            # policy -> list of throughput values (one per cache size, in order)
            policy_rows: dict[str, list[float]] = {}

            for cache_size, csv_path in size_files:
                sizes.append(cache_size)
                with csv_path.open(newline="") as fh:
                    reader = csv.DictReader(fh)
                    for row in reader:
                        policy   = row["Policy"]
                        requests = float(row["Requests"])
                        time_ms  = float(row["Time"])
                        throughput = requests / time_ms if time_ms else 0.0
                        policy_rows.setdefault(policy, []).append(throughput)

            out_path = csv_dir / f"{trace_name}_sample{sample_n}_throughput.csv"
            with out_path.open("w", newline="") as fh:
                writer = csv.writer(fh)
                writer.writerow(["Policy"] + [f"{s:,}" for s in sizes])
                for policy, values in policy_rows.items():
                    writer.writerow([policy] + [f"{v:.2f}" for v in values])

            print(f"  OK  {out_path.name}")
            total += 1

    print(f"\nDone. {total} throughput CSVs generated.")


if __name__ == "__main__":
    main()
