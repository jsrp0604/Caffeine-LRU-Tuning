#!/usr/bin/env bash
# glcache_sim.sh
# Sweeps sampled.LRU sample sizes 1–10 across 5 cache sizes for the GL-Cache trace.
# Renames output files immediately after each run to prevent overwrites.
#
# Run from your Caffeine project root:
#   bash glcache_sim.sh

set -euo pipefail

TRACE_PATH="lirs:C:/Users/juans/Downloads/caffeine/traces/glcache_keyonly.trace.gz"
TRACE_FORMAT="lirs"

# Where Caffeine writes its simulate output
CAFFEINE_OUT="/c/Users/juans/Downloads/caffeine/simulator/build/reports/simulate"

# Where we want our renamed results to live
RESULTS_DIR="/c/Users/juans/Downloads/caffeine/simulator/build/reports/glcache"

# Pre-calculated cache sizes (entries) for each % of the GL-Cache workload
# Total lines: 122,804,013
# .001%: 1_228 | .01%: 12_280 | .1%: 122_804 | 1%: 1_228_040 | 10%: 12_280_401
MAX_SIZES="1_228,12_280,122_804,1_228_040,12_280_401"
SIZE_LABELS=("1228" "12280" "122804" "1228040" "12280401")

mkdir -p "$RESULTS_DIR/csv" "$RESULTS_DIR/graphs"

echo "========================================"
echo " GL-Cache simulation sweep"
echo " Policies: opt.Clairvoyant, linked.Lru, sampled.Lru"
echo " Cache sizes: .001%, .01%, .1%, 1%, 10%"
echo " Sample sizes: 1 to 10"
echo " Results → ${RESULTS_DIR}"
echo "========================================"

for sample_size in $(seq 1 10); do
  title="glcache_sample${sample_size}"
  echo ""
  echo "▶ Running sample_size=${sample_size} → ${title}"

  ./gradlew simulator:simulate -q \
    -PjvmArgs="-Xmx16g" \
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
echo " GL-Cache sweep complete."
echo " Results saved to: ${RESULTS_DIR}"
echo "   Combined : csv/glcache_sample{1..10}.csv"
echo "   Charts   : graphs/glcache_sample{1..10}.png"
echo "   Per-size : csv/glcache_sample{1..10}_size{N}.csv"
echo "========================================"
