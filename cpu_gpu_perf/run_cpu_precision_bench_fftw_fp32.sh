#!/usr/bin/env bash
set -euo pipefail

PY_FILE=${1:-cpu_precision_bench_fftw_fp32.py}
LOG_FILE=${2:-cpu_precision_bench_fftw_fp32_log.txt}

BATCHES=${BATCHES:-"1 2 4 6 8 10"}
TORCH_THREADS=${TORCH_THREADS:-0}
FFTW_THREADS=${FFTW_THREADS:-1}
ROUNDS=${ROUNDS:-100}
WARMUP=${WARMUP:-10}

# Set FORCE_FFTW_LOOP=1 to skip the batched FFTW plan attempt.
FORCE_FFTW_LOOP=${FORCE_FFTW_LOOP:-0}

printf "Running CPU precision benchmark\n" | tee -a "$LOG_FILE"
printf "PY_FILE=%s\n" "$PY_FILE" | tee -a "$LOG_FILE"
printf "LOG_FILE=%s\n" "$LOG_FILE" | tee -a "$LOG_FILE"
printf "BATCHES=%s\n" "$BATCHES" | tee -a "$LOG_FILE"
printf "TORCH_THREADS=%s\n" "$TORCH_THREADS" | tee -a "$LOG_FILE"
printf "FFTW_THREADS=%s\n" "$FFTW_THREADS" | tee -a "$LOG_FILE"
printf "ROUNDS=%s\n" "$ROUNDS" | tee -a "$LOG_FILE"
printf "WARMUP=%s\n" "$WARMUP" | tee -a "$LOG_FILE"
printf "FORCE_FFTW_LOOP=%s\n" "$FORCE_FFTW_LOOP" | tee -a "$LOG_FILE"

for b in $BATCHES; do
    printf "\n========== batch=%s ==========\n" "$b" | tee -a "$LOG_FILE"

    if [[ "$FORCE_FFTW_LOOP" == "1" ]]; then
        python "$PY_FILE" \
            --batch "$b" \
            --log "$LOG_FILE" \
            --torch_threads "$TORCH_THREADS" \
            --fftw_threads "$FFTW_THREADS" \
            --rounds "$ROUNDS" \
            --warmup "$WARMUP" \
            --force_fftw_loop
    else
        python "$PY_FILE" \
            --batch "$b" \
            --log "$LOG_FILE" \
            --torch_threads "$TORCH_THREADS" \
            --fftw_threads "$FFTW_THREADS" \
            --rounds "$ROUNDS" \
            --warmup "$WARMUP"
    fi
done

printf "\nDone. Log saved to %s\n" "$LOG_FILE" | tee -a "$LOG_FILE"
