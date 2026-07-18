#!/usr/bin/env bash
# umass_sim.sh
# Sweeps sampled.LRU sample sizes 1–10 across 5 cache sizes for the UMass Financial1 trace.
# Renames output files immediately after each run to prevent overwrites.
#
# Run from your Caffeine project root:
#   bash umass_sim.sh

set -euo pipefail

TRACE_PATH="umass-storage:C:/Users/juans/Downloads/caffeine/traces/Financial1.spc.bz2"
TRACE_FORMAT="umass-storage"

# Where Caffeine writes its simulate output
CAFFEINE_OUT="/c/Users/juans/Downloads/caffeine/simulator/build/reports/simulate"

# Where we want our renamed results to live
RESULTS_DIR="/c/Users/juans/Downloads/caffeine/simulator/build/reports/umass_financial"

# Pre-calculated cache sizes (entries) for each % of the UMass Financial1 workload
# Total lines: 1,110,010
# .001%: 7 | .01%: 71 | .1%: 710 | 1%: 7_109 | 10%: 71_090
MAX_SIZES="11_100,111_001,222_002,333_003,444_004,555_005,666_006,777_007,888_008,999_009"
SIZE_LABELS=("11100" "111001" "222002" "333003" "444004" "555005" "666006" "777007" "888008" "999009")

mkdir -p "$RESULTS_DIR/csv" "$RESULTS_DIR/graphs"

echo "========================================"
echo " UMass Financial1 simulation sweep"
echo " Policies: linked.Lru, sampled.Lru"
echo " Cache sizes: 1%, 10%, 20%, 30%, 40%, 50%, 60%, 70%, 80%, 90%"
echo " Sample sizes: 1 to 10"
echo " Results → ${RESULTS_DIR}"
echo "========================================"

for sample_size in $(seq 1 10); do
  title="umass_financial_sample${sample_size}"
  echo ""

  if [[ "${sample_size}" -eq 1 ]]; then
    echo "▶ Warm-up run (discarded) for sample_size=${sample_size} — JVM/JIT cold start skews throughput timing"
    ./gradlew simulator:simulate -q \
      --maximumSize="${MAX_SIZES}" \
      --title="${title}" \
      -Dcaffeine.simulator.sampled.size="${sample_size}" \
      -Dcaffeine.simulator.files.paths.0="${TRACE_PATH}" \
      -Dcaffeine.simulator.files.format="${TRACE_FORMAT}"
    echo "   (warm-up output discarded, will be overwritten below)"
  fi

  echo "▶ Running sample_size=${sample_size} → ${title}"

  ./gradlew simulator:simulate -q \
    --maximumSize="${MAX_SIZES}" \
    --title="${title}" \
    -Dcaffeine.simulator.sampled.size="${sample_size}" \
    -Dcaffeine.simulator.files.paths.0="${TRACE_PATH}" \
    -Dcaffeine.simulator.files.format="${TRACE_FORMAT}" \

  # Rename combined CSV and chart before next run overwrites them
  mv "${CAFFEINE_OUT}/hit_rate.csv" \
     "${RESULTS_DIR}/csv/${title}.csv"
  mv "${CAFFEINE_OUT}/hit_rate.png" \
     "${RESULTS_DIR}/graphs/${title}.png"

  # Rename per-size CSVs
  for size in "${SIZE_LABELS[@]}"; do
    if [[ -f "${CAFFEINE_OUT}/hit_rate_${size}.csv" ]]; then
      mv "${CAFFEINE_OUT}/hit_rate_${size}.csv" \
         "${RESULTS_DIR}/csv/${title}_size${size}.csv"
    fi
  done

  echo "   ✓ Saved: ${title}.csv / ${title}.png"
done

echo ""
echo "========================================"
echo " UMass Financial1 sweep complete."
echo " Results saved to: ${RESULTS_DIR}"
echo "   Combined : csv/umass_financial_sample{1..10}.csv"
echo "   Charts   : graphs/umass_financial_sample{1..10}.png"
echo "   Per-size : csv/umass_financial_sample{1..10}_size{N}.csv"
echo "========================================"