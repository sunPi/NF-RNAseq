#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
MATRIX_DIR=""
OUTPUT_DIR=""
CONTRASTS_FILE=""
DB_ROOT=""
ASSEMBLY=""
THREADS=1

die() {
    printf '[gsea] ERROR: %s\n' "$*" >&2
    exit 1
}

while (( $# > 0 )); do
    case "$1" in
        --matrix-dir) MATRIX_DIR="$2"; shift 2 ;;
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        --contrasts-file) CONTRASTS_FILE="$2"; shift 2 ;;
        --db-root) DB_ROOT="$2"; shift 2 ;;
        --assembly) ASSEMBLY="$2"; shift 2 ;;
        --threads) THREADS="$2"; shift 2 ;;
        --results-dir|--samples-file|--design) shift 2 ;;
        --contrast) shift 2 ;;
        *) die "Unknown argument: $1" ;;
    esac
done

[[ -d "${MATRIX_DIR}/DGE/contrasts" ]] ||
    die "DGE contrast results not found: ${MATRIX_DIR}/DGE/contrasts"
[[ -s "$CONTRASTS_FILE" ]] || die "Validated contrasts not found: $CONTRASTS_FILE"
[[ -n "$DB_ROOT" && -n "$ASSEMBLY" ]] || die "--db-root and --assembly are required"
[[ "$THREADS" =~ ^[1-9][0-9]*$ ]] || die "--threads must be a positive integer"

MODULE_CONFIG="${DB_ROOT}/shared/gsea_module/config/${ASSEMBLY}.config"
[[ -s "$MODULE_CONFIG" ]] || die "GSEA is not installed for $ASSEMBLY: $MODULE_CONFIG"
# shellcheck disable=SC1090
source "$MODULE_CONFIG"
[[ -n "${GSEA_CONDA_ENV:-}" ]] || die "GSEA_CONDA_ENV is missing from $MODULE_CONFIG"
[[ -s "${GSEA_GMT:-}" ]] || die "Configured GSEA GMT was not found: ${GSEA_GMT:-unset}"

mkdir -p "$OUTPUT_DIR"
exec conda run --name "$GSEA_CONDA_ENV" Rscript "${SCRIPT_DIR}/run_gsea_module.R" \
    --dge-dir "${MATRIX_DIR}/DGE/contrasts" \
    --contrasts "$CONTRASTS_FILE" \
    --gmt "$GSEA_GMT" \
    --collection "$GSEA_COLLECTION" \
    --gmt-sha256 "$GSEA_GMT_SHA256" \
    --output-dir "$OUTPUT_DIR"
