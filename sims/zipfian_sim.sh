#!/usr/bin/env bash
# zipfian_sim.sh

set -euo pipefail

# Synthetic zipfian generator settings
ZIPF_ITEMS=20000          
ZIPF_CONSTANT=0.99        
SYNTH_EVENTS=200000       
SYNTH_DISTRIBUTION=scrambled-zipfian

CAFFEINE_OUT="/c/Users/juans/Downloads/caffeine/simulator/build/reports/simulate"
RESULTS_DIR="/c/Users/juans/Downloads/caffeine/simulator/build/reports/zipfian"

# 0.1%: 20 | 1%: 200 | 10%: 2,000 | 20%: 4,000 | 30%: 6,000 | 50%: 10,000
MAX_SIZES="20,200,2000,4000,6000,10000"
SIZE_LABELS=("20" "200" "2000" "4000" "6000" "10000")

mkdir -p "$RESULTS_DIR/csv" "$RESULTS_DIR/graphs"

echo "========================================"
echo " Zipfian synthetic simulation sweep"
echo " Policies: linked.Lru, sampled.Lru"
echo " Zipfian items: ${ZIPF_ITEMS}  constant: ${ZIPF_CONSTANT}"
echo " Cache sizes: 0.1%, 1%, 10%, 20%, 30%, 50%"
echo " Sample sizes: 1 to 10"
echo " Results → ${RESULTS_DIR}"
echo "========================================"

for sample_size in $(seq 1 10); do
  title="zipfian_sample${sample_size}"
  echo ""
  echo "▶ Running sample_size=${sample_size} → ${title}"

  ./gradlew simulator:simulate -q \
    --maximumSize="${MAX_SIZES}" \
    --title="${title}" \
    -Dcaffeine.simulator.sampled.size="${sample_size}" \
    -Dcaffeine.simulator.trace.source=synthetic \
    -Dcaffeine.simulator.synthetic.distribution="${SYNTH_DISTRIBUTION}" \
    -Dcaffeine.simulator.synthetic.events="${SYNTH_EVENTS}" \
    -Dcaffeine.simulator.synthetic.zipfian.items="${ZIPF_ITEMS}" \
    -Dcaffeine.simulator.synthetic.zipfian.constant="${ZIPF_CONSTANT}"

  mv "${CAFFEINE_OUT}/hit_rate.csv" \
     "${RESULTS_DIR}/csv/${title}.csv"
  mv "${CAFFEINE_OUT}/hit_rate.png" \
     "${RESULTS_DIR}/graphs/${title}.png"

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
echo " Zipfian sweep complete."
echo " Results saved to: ${RESULTS_DIR}"
echo "   Combined : csv/zipfian_sample{1..10}.csv"
echo "   Charts   : graphs/zipfian_sample{1..10}.png"
echo "   Per-size : csv/zipfian_sample{1..10}_size{N}.csv"
echo "========================================"