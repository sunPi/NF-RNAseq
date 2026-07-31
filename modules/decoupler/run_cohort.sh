#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
MATRIX_DIR=""; OUTPUT_DIR=""; DB_ROOT=""; ASSEMBLY=""; DESIGN=""; CONTRASTS=""; THREADS=1
while (( $# )); do case "$1" in
  --matrix-dir) MATRIX_DIR="$2"; shift 2;; --output-dir) OUTPUT_DIR="$2"; shift 2;;
  --db-root) DB_ROOT="$2"; shift 2;; --assembly) ASSEMBLY="$2"; shift 2;;
  --design) DESIGN="$2"; shift 2;; --contrasts-file) CONTRASTS="$2"; shift 2;;
  --threads) THREADS="$2"; shift 2;;
  --results-dir|--samples-file|--contrast) shift 2;;
  *) printf '[decoupler] ERROR: Unknown argument: %s\n' "$1" >&2; exit 1;; esac; done
source "$DB_ROOT/shared/decoupler_module/config/${ASSEMBLY}.config"
[[ "$THREADS" =~ ^[1-9][0-9]*$ ]] || { printf '[decoupler] ERROR: --threads must be a positive integer\n' >&2; exit 1; }
args=(--expression "$MATRIX_DIR/annotated/deduplicated/gene_TPM.highest.tsv"
  --collectri "$DECOUPLER_COLLECTRI" --progeny "$DECOUPLER_PROGENY"
  --output-dir "$OUTPUT_DIR" --threads "$THREADS")
[[ -z "$DESIGN" ]] || args+=(--design "$DESIGN" --contrasts "$CONTRASTS")
export OMP_NUM_THREADS="$THREADS"
export OPENBLAS_NUM_THREADS="$THREADS"
export MKL_NUM_THREADS="$THREADS"
export VECLIB_MAXIMUM_THREADS="$THREADS"
export NUMEXPR_NUM_THREADS="$THREADS"
exec conda run --name "$DECOUPLER_CONDA_ENV" \
  Rscript "$SCRIPT_DIR/run_decoupler.R" "${args[@]}"
