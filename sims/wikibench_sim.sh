#!/usr/bin/env bash
# wikibench_sim.sh
# Sweeps sampled.LRU sample sizes 1–10 across 5 cache sizes for the WikiBench trace.
# Uses simulator:simulate so each run produces a combined CSV + chart.
#
# Run from your Caffeine project root:
#   bash wikibench_sim.sh

set -euo pipefail
 
TRACE_PATH="wikipedia:C:/Users/juans/Downloads/caffeine/traces/wiki.1190153705.gz"
TRACE_FORMAT="wikipedia"
 
# Where Caffeine writes its simulate output
CAFFEINE_OUT="/c/Users/juans/Downloads/caffeine/simulator/build/reports/simulate"
 
# Where we want our renamed results to live
RESULTS_DIR="/c/Users/juans/Downloads/caffeine/simulator/build/reports/wikibench"
 
# Pre-calculated cache sizes (entries) for each % of the WikiBench workload
# Total unique keys: 1,712,461
# .001%: 17 | .01%: 171 | .1%: 1_712 | 1%: 17_124 | 10%: 171_246
MAX_SIZES="17,171,1_712,17_124,171_246,342_492,513_738,684_984,856_230,1_027_476"
SIZE_LABELS=("17" "171" "1712" "17124" "171246" "342492" "513738" "684984" "856230" "1027476")
 
mkdir -p "$RESULTS_DIR/csv" "$RESULTS_DIR/graphs"
 
echo "========================================"
echo " WikiBench simulation sweep"
echo " Policies: opt.Clairvoyant, linked.Lru, sampled.Lru"
echo " Cache sizes: .001%, .01%, .1%, 1%, 10%, 20%, 30%, 40%, 50%, 60%"
echo " Sample sizes: 1 to 10"
echo " Results → ${RESULTS_DIR}"
echo "========================================"

for sample_size in $(seq 1 10); do
  title="wikibench_sample${sample_size}"
  echo ""
  echo "▶ Running sample_size=${sample_size} → report title: ${title}"

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
echo " WikiBench sweep complete."
echo " Results saved to: ${RESULTS_DIR}"
echo "   Combined : csv/wikibench_sample{1..10}.csv"
echo "   Charts   : graphs/wikibench_sample{1..10}.png"
echo "   Per-size : csv/wikibench_sample{1..10}_size{N}.csv"
echo "========================================"
