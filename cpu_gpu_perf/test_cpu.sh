#!/usr/bin/env bash
set -euo pipefail

PY_FILE=${1:-torch_fp16_bfly_nn_cpu.py}
LOG_FILE=${2:-cpu_precision_bench_log.txt}

BATCHES=${BATCHES:-"1 2 4 6 8 10"}
TORCH_THREADS=${TORCH_THREADS:-0}
FFTW_THREADS=${FFTW_THREADS:-1}


{
  echo "Running CPU precision benchmark"
  echo "PY_FILE=${PY_FILE}"
  echo "LOG_FILE=${LOG_FILE}"
  echo "BATCHES=${BATCHES}"
  echo "TORCH_THREADS=${TORCH_THREADS}"
  echo "FFTW_THREADS=${FFTW_THREADS}"
} | tee -a "${LOG_FILE}"

for b in ${BATCHES}; do
  echo "" | tee -a "${LOG_FILE}"
  echo "========== batch=${b} ==========" | tee -a "${LOG_FILE}"
  python "${PY_FILE}" \
    --batch "${b}" \
    --log "${LOG_FILE}" \
    --torch-threads "${TORCH_THREADS}" \
    --fftw-threads "${FFTW_THREADS}"
done

echo "" | tee -a "${LOG_FILE}"
echo "Done. Log saved to ${LOG_FILE}" | tee -a "${LOG_FILE}"
