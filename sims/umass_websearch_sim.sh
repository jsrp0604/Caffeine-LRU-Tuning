#!/usr/bin/env bash
# umass_websearch_sim.sh
# Sweeps sampled.LRU sample sizes 1–10 across 5 cache sizes for the UMass WebSearch trace.
# Renames output files immediately after each run to prevent overwrites.
#
# Run from your Caffeine project root:
#   bash umass_websearch_sim.sh

set -euo pipefail

TRACE_PATH="umass-storage:C:/Users/juans/Downloads/caffeine/traces/WebSearch2.spc.bz2"
TRACE_FORMAT="umass-storage"

# Where Caffeine writes its simulate output
CAFFEINE_OUT="/c/Users/juans/Downloads/caffeine/simulator/build/reports/simulate"

# Where we want our renamed results to live
RESULTS_DIR="/c/Users/juans/Downloads/caffeine/simulator/build/reports/umass_websearch"

# Pre-calculated cache sizes (entries) for each % of the UMass WebSearch workload
# Total lines: 13_546_784
# 20%: 2_709_356 | 30%: 4_064_035 | 40%: 5_418_713 | 50%: 6_773_392 | 60%: 8_128_070
MAX_SIZES="2_709_356,4_064_035,5_418_713,6_773_392,8_128_070,9_482_748,10_837_427,12_192_105,12_869_444"
SIZE_LABELS=("2709356" "4064035" "5418713" "6773392" "8128070" "9482748" "10837427" "12192105" "12869444")

mkdir -p "$RESULTS_DIR/csv" "$RESULTS_DIR/graphs"

echo "========================================"
echo " UMass WebSearch simulation sweep"
echo " Policies: opt.Clairvoyant, linked.Lru, sampled.Lru"
echo " Cache sizes: 20%, 30%, 40%, 50%, 60%, 70%, 80%, 90%, 95%"
echo " Sample sizes: 1 to 10"
echo " Results → ${RESULTS_DIR}"
echo "========================================"

for sample_size in $(seq 1 10); do
  title="umass_websearch_sample${sample_size}"
  echo ""
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
echo " UMass WebSearch sweep complete."
echo " Results saved to: ${RESULTS_DIR}"
echo "   Combined : csv/umass_websearch_sample{1..10}.csv"
echo "   Charts   : graphs/umass_websearch_sample{1..10}.png"
echo "   Per-size : csv/umass_websearch_sample{1..10}_size{N}.csv"
echo "========================================"
