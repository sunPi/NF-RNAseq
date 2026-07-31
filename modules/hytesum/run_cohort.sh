#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
MATRIX_DIR=""; OUTPUT_DIR=""; SAMPLES_FILE=""; DB_ROOT=""; ASSEMBLY=""
DESIGN=""; CONTRASTS_FILE=""; THREADS=1

die() { printf '[hytesum] ERROR: %s\n' "$*" >&2; exit 1; }

while (( $# > 0 )); do
    case "$1" in
        --matrix-dir) MATRIX_DIR="$2"; shift 2 ;;
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        --samples-file) SAMPLES_FILE="$2"; shift 2 ;;
        --db-root) DB_ROOT="$2"; shift 2 ;;
        --assembly) ASSEMBLY="$2"; shift 2 ;;
        --threads) THREADS="$2"; shift 2 ;;
        --design) DESIGN="$2"; shift 2 ;;
        --contrasts-file) CONTRASTS_FILE="$2"; shift 2 ;;
        --results-dir|--contrast) shift 2 ;;
        *) die "Unknown argument: $1" ;;
    esac
done

EXPRESSION="${MATRIX_DIR}/annotated/deduplicated/gene_TPM.highest.tsv"
[[ -s "$EXPRESSION" ]] || die "Annotated deduplicated TPM matrix not found: $EXPRESSION"
[[ -s "$SAMPLES_FILE" ]] || die "QC-included sample list not found: $SAMPLES_FILE"
[[ "$THREADS" =~ ^[1-9][0-9]*$ ]] || die "--threads must be a positive integer"
CONFIG="${DB_ROOT}/shared/hytesum_module/config/${ASSEMBLY}.config"
[[ -s "$CONFIG" ]] || die "HyTEsum is not installed for $ASSEMBLY: $CONFIG"
# shellcheck disable=SC1090
source "$CONFIG"
[[ -n "${HYTESUM_CONDA_ENV:-}" ]] || die "HYTESUM_CONDA_ENV is missing from $CONFIG"
[[ -s "${HYTESUM_GMT:-}" ]] || die "HyTE signature GMT not found: ${HYTESUM_GMT:-unset}"

arguments=(--expression "$EXPRESSION" --samples-file "$SAMPLES_FILE"
    --gmt "$HYTESUM_GMT" --gmt-sha256 "$HYTESUM_GMT_SHA256"
    --collection "$HYTESUM_COLLECTION" --output-dir "$OUTPUT_DIR")
[[ -z "$DESIGN" ]] || arguments+=(--design "$DESIGN" --contrasts "$CONTRASTS_FILE")
export OMP_NUM_THREADS="$THREADS" OPENBLAS_NUM_THREADS="$THREADS" MKL_NUM_THREADS="$THREADS"
mkdir -p "$OUTPUT_DIR"
exec conda run --name "$HYTESUM_CONDA_ENV" Rscript \
    "${SCRIPT_DIR}/run_hytesum.R" "${arguments[@]}"
