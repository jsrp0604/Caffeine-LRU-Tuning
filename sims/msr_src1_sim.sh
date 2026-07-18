#!/usr/bin/env bash
# msr_src1_sim.sh
# Sweeps sampled.LRU sample sizes 1–10 across 6 cache sizes for the MSR Cambridge "src1" trace.
# Renames output files immediately after each run to prevent overwrites.
#
# Run from your Caffeine project root:
#   bash msr_src1_sim.sh

set -euo pipefail

TRACE_PATH="lirs:D:/msr_src1_lirs.trace.gz"
TRACE_FORMAT="lirs"

# Where Caffeine writes its simulate output
CAFFEINE_OUT="/c/Users/juans/Downloads/caffeine/simulator/build/reports/simulate"

# Where we want our renamed results to live
RESULTS_DIR="/c/Users/juans/Downloads/caffeine/simulator/build/reports/msr_src1"

# Pre-calculated cache sizes (entries) for each % of the MSR Cambridge src1 workload
# Total unique objects: 10,857,542
# 10%: 1_085_754 | 20%: 2_171_508 | 30%: 3_257_262 | 40%: 4_343_016 | 50%: 5_428_771 | 60%: 6_514_525
MAX_SIZES="1_085_754,2_171_508,3_257_262,4_343_016,5_428_771,6_514_525"
SIZE_LABELS=("1085754" "2171508" "3257262" "4343016" "5428771" "6514525")

mkdir -p "$RESULTS_DIR/csv" "$RESULTS_DIR/graphs"

echo "========================================"
echo " MSR Cambridge src1 simulation sweep"
echo " Policies: linked.Lru, sampled.Lru"
echo " Cache sizes: 10%, 20%, 30%, 40%, 50%, 60%"
echo " Sample sizes: 1 to 10"
echo " Results → ${RESULTS_DIR}"
echo "========================================"

for sample_size in $(seq 1 10); do
  title="msr_src1_sample${sample_size}"
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
echo " MSR Cambridge src1 sweep complete."
echo " Results saved to: ${RESULTS_DIR}"
echo "   Combined : csv/msr_src1_sample{1..10}.csv"
echo "   Charts   : graphs/msr_src1_sample{1..10}.png"
echo "   Per-size : csv/msr_src1_sample{1..10}_size{N}.csv"
echo "========================================"
