#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
MATRIX_DIR=""
OUTPUT_DIR=""
DESIGN=""
CONTRASTS_FILE=""
DB_ROOT=""
ASSEMBLY=""
THREADS=1

die() {
    printf '[dge] ERROR: %s\n' "$*" >&2
    exit 1
}

while (( $# > 0 )); do
    case "$1" in
        --matrix-dir) MATRIX_DIR="$2"; shift 2 ;;
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        --design) DESIGN="$2"; shift 2 ;;
        --contrasts-file) CONTRASTS_FILE="$2"; shift 2 ;;
        --db-root) DB_ROOT="$2"; shift 2 ;;
        --assembly) ASSEMBLY="$2"; shift 2 ;;
        --threads) THREADS="$2"; shift 2 ;;
        --results-dir|--samples-file) shift 2 ;;
        --contrast) shift 2 ;;
        *) die "Unknown argument: $1" ;;
    esac
done

COUNTS="${MATRIX_DIR}/annotated/gene_counts.tsv"
[[ -s "$COUNTS" ]] || die "Canonical annotated integer-count matrix not found: $COUNTS"
[[ -s "$DESIGN" ]] || die "Validated design not found: $DESIGN"
[[ -s "$CONTRASTS_FILE" ]] || die "Validated contrasts not found: $CONTRASTS_FILE"
[[ -n "$DB_ROOT" && -n "$ASSEMBLY" ]] || die "--db-root and --assembly are required"
[[ "$THREADS" =~ ^[1-9][0-9]*$ ]] || die "--threads must be a positive integer"

MODULE_CONFIG="${DB_ROOT}/shared/dge_module/config/${ASSEMBLY}.config"
[[ -s "$MODULE_CONFIG" ]] || die "DGE is not installed for $ASSEMBLY: $MODULE_CONFIG"
# shellcheck disable=SC1090
source "$MODULE_CONFIG"
[[ -n "${DGE_CONDA_ENV:-}" ]] || die "DGE_CONDA_ENV is missing from $MODULE_CONFIG"

mkdir -p "$OUTPUT_DIR"
exec conda run --name "$DGE_CONDA_ENV" Rscript "${SCRIPT_DIR}/run_dge.R" \
    --counts "$COUNTS" \
    --design "$DESIGN" \
    --contrasts "$CONTRASTS_FILE" \
    --output-dir "$OUTPUT_DIR" \
    --threads "$THREADS"
