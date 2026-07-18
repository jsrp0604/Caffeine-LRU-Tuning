#!/usr/bin/env bash
# memcached_cluster01_sim.sh
# Sweeps sampled.LRU sample sizes 1–10 across 5 cache sizes for the Memcached Cluster 01 trace.
# Renames output files immediately after each run to prevent overwrites.
#
# Run from your Caffeine project root:
#   bash memcached_cluster01_sim.sh

set -euo pipefail

TRACE_PATH="lirs:C:/Users/juans/Downloads/caffeine/traces/memcached_keyonly.trace.gz"
TRACE_FORMAT="lirs"

# Where Caffeine writes its simulate output
CAFFEINE_OUT="/c/Users/juans/Downloads/caffeine/simulator/build/reports/simulate"

# Where we want our renamed results to live
RESULTS_DIR="/c/Users/juans/Downloads/caffeine/simulator/build/reports/memcached_cluster01"

# Pre-calculated cache sizes (entries) for each % of the Memcached Cluster 01 workload
# Total lines: 153,919,329
# 1%: 1539193 | 5%: 7695966 | 10%: 15391933 | 20%: 30783866 | 30%: 46175799
MAX_SIZES="15_391,76_959,153_919,307_838,461_757"
SIZE_LABELS=("15391" "76959" "153919" "307838" "461757")

mkdir -p "$RESULTS_DIR/csv" "$RESULTS_DIR/graphs"

echo "========================================"
echo " Memcached Cluster 01 simulation sweep"
echo " Policies: opt.Clairvoyant, linked.Lru, sampled.Lru"
echo " Cache sizes: 1%, 5%, 10%, 20%, 30%"
echo " Sample sizes: 1 to 10"
echo " Results → ${RESULTS_DIR}"
echo "========================================"

for sample_size in $(seq 1 10); do
  title="memcached_cluster01_sample${sample_size}"
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
echo " Memcached Cluster 01 sweep complete."
echo " Results saved to: ${RESULTS_DIR}"
echo "   Combined : csv/memcached_cluster01_sample{1..10}.csv"
echo "   Charts   : graphs/memcached_cluster01_sample{1..10}.png"
echo "   Per-size : csv/memcached_cluster01_sample{1..10}_size{N}.csv"
echo "========================================"
