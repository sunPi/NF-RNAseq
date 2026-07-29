#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
MATRIX_DIR=""
OUTPUT_DIR=""
SAMPLES_FILE=""
DESIGN=""
CONTRASTS_FILE=""
DB_ROOT=""
ASSEMBLY=""
THREADS=1

die() {
    printf '[ssgsva] ERROR: %s\n' "$*" >&2
    exit 1
}

while (( $# > 0 )); do
    case "$1" in
        --matrix-dir) MATRIX_DIR="$2"; shift 2 ;;
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        --samples-file) SAMPLES_FILE="$2"; shift 2 ;;
        --design) DESIGN="$2"; shift 2 ;;
        --contrasts-file) CONTRASTS_FILE="$2"; shift 2 ;;
        --db-root) DB_ROOT="$2"; shift 2 ;;
        --assembly) ASSEMBLY="$2"; shift 2 ;;
        --threads) THREADS="$2"; shift 2 ;;
        --results-dir) shift 2 ;;
        --contrast) shift 2 ;;
        *) die "Unknown argument: $1" ;;
    esac
done

EXPRESSION="${MATRIX_DIR}/annotated/deduplicated/gene_TPM.highest.tsv"
[[ -s "$EXPRESSION" ]] ||
    die "Highest-expression symbol-deduplicated TPM matrix not found: $EXPRESSION"
[[ -s "$SAMPLES_FILE" ]] || die "QC-included sample list not found: $SAMPLES_FILE"
[[ -n "$DB_ROOT" && -n "$ASSEMBLY" ]] || die "--db-root and --assembly are required"
[[ "$THREADS" =~ ^[1-9][0-9]*$ ]] || die "--threads must be a positive integer"
if [[ -n "$DESIGN" ]]; then
    [[ -s "$DESIGN" ]] || die "Validated design not found: $DESIGN"
    [[ -s "$CONTRASTS_FILE" ]] || die "Validated contrasts not found: $CONTRASTS_FILE"
fi

MODULE_CONFIG="${DB_ROOT}/shared/ssgsva_module/config/${ASSEMBLY}.config"
[[ -s "$MODULE_CONFIG" ]] || die "ssGSVA is not installed for $ASSEMBLY: $MODULE_CONFIG"
# shellcheck disable=SC1090
source "$MODULE_CONFIG"
[[ -n "${SSGSVA_CONDA_ENV:-}" ]] ||
    die "SSGSVA_CONDA_ENV is missing from $MODULE_CONFIG"
[[ -s "${SSGSVA_GMT:-}" ]] ||
    die "Configured ssGSVA GMT was not found: ${SSGSVA_GMT:-unset}"

arguments=(
    --expression "$EXPRESSION"
    --samples-file "$SAMPLES_FILE"
    --gmt "$SSGSVA_GMT"
    --collection "$SSGSVA_COLLECTION"
    --gmt-sha256 "$SSGSVA_GMT_SHA256"
    --method "$SSGSVA_METHOD"
    --output-dir "$OUTPUT_DIR"
)
if [[ -n "$DESIGN" ]]; then
    arguments+=(--design "$DESIGN" --contrasts "$CONTRASTS_FILE")
fi

mkdir -p "$OUTPUT_DIR"
exec conda run --name "$SSGSVA_CONDA_ENV" Rscript \
    "${SCRIPT_DIR}/run_ssgsva_module.R" "${arguments[@]}"
