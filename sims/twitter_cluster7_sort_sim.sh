#!/usr/bin/env bash
# twitter_cluster7_sim.sh
# Sweeps sampled.LRU sample sizes 1–10 across 5 cache sizes for the Twitter Cluster 7 (sorted) trace.
# Renames output files immediately after each run to prevent overwrites.
#
# Run from your Caffeine project root:
#   bash twitter_cluster7_sim.sh

set -euo pipefail

#TRACE_PATH="lirs:C:/Users/juans/Downloads/caffeine/traces/cluster7_keyonly.trace.gz"
TRACE_PATH="lirs:D:/cluster7_keyonly.trace.gz"
TRACE_FORMAT="lirs"

# Where Caffeine writes its simulate output
CAFFEINE_OUT="/c/Users/juans/Downloads/caffeine/simulator/build/reports/simulate"

# Where we want our renamed results to live
RESULTS_DIR="/c/Users/juans/Downloads/caffeine/simulator/build/reports/twitter_cluster7"

# Pre-calculated cache sizes (entries) for each % of the Twitter Cluster 7 (sorted) workload
# Total lines: 4,467,939
# .001%: 44 | .01%: 446 | .1%: 4_467 | 1%: 44_679 | 10%: 446793
MAX_SIZES="44,446,4_467,44_679,446_793,893_587,1_116_984,1_340_381,1_787_175,2_233_969,2_680_763,3_574_351,4_021_145"
SIZE_LABELS=("44" "446" "446" "4467" "446793" "893587" "1116984" "1340381" "1787175" "2233969" "2680763" "3574351" "4021145")

mkdir -p "$RESULTS_DIR/csv" "$RESULTS_DIR/graphs"

echo "========================================"
echo " Twitter Cluster 7 (sorted) simulation sweep"
echo " Policies: opt.Clairvoyant, linked.Lru, sampled.Lru"
echo " Cache sizes: .001%, .01%, .1%, 1%, 10%, 20%, 30%, 40%, 50%, 60%, 80%, 90%"
echo " Sample sizes: 1 to 10"
echo " Results → ${RESULTS_DIR}"
echo "========================================"

for sample_size in $(seq 1 10); do
  title="twitter_cluster7_sample${sample_size}"
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
echo " Twitter Cluster 7 (sorted) sweep complete."
echo " Results saved to: ${RESULTS_DIR}"
echo "   Combined : csv/twitter_cluster7_sample{1..10}.csv"
echo "   Charts   : graphs/twitter_cluster7_sample{1..10}.png"
echo "   Per-size : csv/twitter_cluster7_sample{1..10}_size{N}.csv"
echo "========================================"
