#!/usr/bin/env bash
# meta_kv_sim.sh
# Sweeps sampled.LRU sample sizes 1–10 across 5 cache sizes for the Meta KV trace.
# Renames output files immediately after each run to prevent overwrites.
#
# Run from your Caffeine project root:
#   bash meta_kv_sim.sh

set -euo pipefail

TRACE_PATH="lirs:D:/meta_kv_keyonly.trace.gz"
TRACE_FORMAT="lirs"

# Where Caffeine writes its simulate output
CAFFEINE_OUT="/c/Users/juans/Downloads/caffeine/simulator/build/reports/simulate"

# Where we want our renamed results to live
RESULTS_DIR="/c/Users/juans/Downloads/caffeine/simulator/build/reports/meta_kv"

# Pre-calculated cache sizes (entries) for each % of the Meta KV workload
# Total lines: 52,460,218
# .0001%: 52 | .001%: 524 | .01%: 5_246 | .1%: 52_460 | 1%: 524_602
MAX_SIZES="52,524,5_246,52_460,524_602,5_246_021,10_492_043,13_115_054"
SIZE_LABELS=("52" "524" "5246" "52460" "524602" "5246021" "10492043" "13115054")

mkdir -p "$RESULTS_DIR/csv" "$RESULTS_DIR/graphs"

echo "========================================"
echo " Meta KV simulation sweep"
echo " Policies: linked.Lru, sampled.Lru"
echo " Cache sizes: .0001%, .001%, .01%, .1%, 1%, 10%, 20%, 25%"
echo " Sample sizes: 1 to 10"
echo " Results → ${RESULTS_DIR}"
echo "========================================"

for sample_size in $(seq 1 10); do
  title="meta_kv_sample${sample_size}"
  echo ""

  # if [[ "${sample_size}" -eq 1 ]]; then
  #   echo "▶ Warm-up run (discarded) for sample_size=${sample_size} — JVM/JIT cold start skews throughput timing"
  #   ./gradlew simulator:simulate -q \
  #     --maximumSize="${MAX_SIZES}" \
  #     --title="${title}" \
  #     -Dcaffeine.simulator.sampled.size="${sample_size}" \
  #     -Dcaffeine.simulator.files.paths.0="${TRACE_PATH}" \
  #     -Dcaffeine.simulator.files.format="${TRACE_FORMAT}"
  #   echo "   (warm-up output discarded, will be overwritten below)"
  # fi

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
echo " Meta KV sweep complete."
echo " Results saved to: ${RESULTS_DIR}"
echo "   Combined : csv/meta_kv_sample{1..10}.csv"
echo "   Charts   : graphs/meta_kv_sample{1..10}.png"
echo "   Per-size : csv/meta_kv_sample{1..10}_size{N}.csv"
echo "========================================"
