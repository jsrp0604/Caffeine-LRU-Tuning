#!/usr/bin/env bash
# msr_web_sim.sh
# Sweeps sampled.LRU sample sizes 1–10 across 9 cache sizes for the MSR Cambridge "web" trace.
# Renames output files immediately after each run to prevent overwrites.
#
# Run from your Caffeine project root:
#   bash msr_web_sim.sh

set -euo pipefail

TRACE_PATH="lirs:D:/msr_web_lirs.trace.gz"
TRACE_FORMAT="lirs"

# Where Caffeine writes its simulate output
CAFFEINE_OUT="/c/Users/juans/Downloads/caffeine/simulator/build/reports/simulate"

# Where we want our renamed results to live
RESULTS_DIR="/c/Users/juans/Downloads/caffeine/simulator/build/reports/msr_web"

# Pre-calculated cache sizes (entries) for each % of the MSR Cambridge web workload
# Total unique objects: 1,605,986
# 10%: 160_598 | 20%: 321_197 | 30%: 481_795 | 40%: 642_394 | 50%: 802_993
# 60%: 963_591 | 70%: 1_124_190 | 80%: 1_284_788 | 90%: 1_445_387
MAX_SIZES="160_598,321_197,481_795,642_394,802_993,963_591,1_124_190,1_284_788,1_445_387"
SIZE_LABELS=("160598" "321197" "481795" "642394" "802993" "963591" "1124190" "1284788" "1445387")

mkdir -p "$RESULTS_DIR/csv" "$RESULTS_DIR/graphs"

echo "========================================"
echo " MSR Cambridge web simulation sweep"
echo " Policies: linked.Lru, sampled.Lru"
echo " Cache sizes: 10%, 20%, 30%, 40%, 50%, 60%, 70%, 80%, 90%"
echo " Sample sizes: 1 to 10"
echo " Results → ${RESULTS_DIR}"
echo "========================================"

for sample_size in $(seq 1 10); do
  title="msr_web_sample${sample_size}"
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
echo " MSR Cambridge web sweep complete."
echo " Results saved to: ${RESULTS_DIR}"
echo "   Combined : csv/msr_web_sample{1..10}.csv"
echo "   Charts   : graphs/msr_web_sample{1..10}.png"
echo "   Per-size : csv/msr_web_sample{1..10}_size{N}.csv"
echo "========================================"
