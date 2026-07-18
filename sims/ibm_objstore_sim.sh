#!/usr/bin/env bash
# ibm_objstore_sim.sh
# Sweeps sampled.LRU sample sizes 1–10 across 5 cache sizes for the IBM Object Store trace.
# Renames output files immediately after each run to prevent overwrites.
#
# Run from your Caffeine project root:
#   bash ibm_objstore_sim.sh

set -euo pipefail

TRACE_PATH="lirs:D:/IBMObjectStoreTrace005_lirs.trace.gz"
TRACE_FORMAT="lirs"

# Where Caffeine writes its simulate output
CAFFEINE_OUT="/c/Users/juans/Downloads/caffeine/simulator/build/reports/simulate"

# Where we want our renamed results to live
RESULTS_DIR="/c/Users/juans/Downloads/caffeine/simulator/build/reports/ibm_objstore"

# Pre-calculated cache sizes (entries) for each % of the IBM Object Store workload
# Total unique keys: 1_695_895 
# .001%: 16 | .01%: 169 | .1%: 1_695 | 1%: 16_958 | 10%: 169_589
MAX_SIZES="16,169,1_695,16_958,84_794,169_589,339_179"
SIZE_LABELS=("16" "169" "1695" "16958" "84794" "169589" "339179")

mkdir -p "$RESULTS_DIR/csv" "$RESULTS_DIR/graphs"

echo "========================================"
echo " IBM Object Store simulation sweep"
echo " Policies: opt.Clairvoyant, linked.Lru, sampled.Lru"
echo " Cache sizes: .001%, .01%, .1%, 1%, 5%, 10%, 20%"
echo " Sample sizes: 1 to 10"
echo " Results → ${RESULTS_DIR}"
echo "========================================"

for sample_size in $(seq 1 10); do
  title="ibm_objstore_sample${sample_size}"
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
echo " IBM Object Store sweep complete."
echo " Results saved to: ${RESULTS_DIR}"
echo "   Combined : csv/ibm_objstore_sample{1..10}.csv"
echo "   Charts   : graphs/ibm_objstore_sample{1..10}.png"
echo "   Per-size : csv/ibm_objstore_sample{1..10}_size{N}.csv"
echo "========================================"
