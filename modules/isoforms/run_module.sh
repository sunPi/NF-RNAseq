#!/usr/bin/env bash

set -Eeuo pipefail

die() {
    printf '[isoforms] ERROR: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage:
  run_module.sh --sample ID --layout single|paired --read1 FILE \
    [--read2 FILE] --output-dir DIR --assembly GRCh37|GRCh38 \
    --db-root DIR [--threads N]

The isoforms module consumes the RSEM isoform result produced by the core
pipeline. FASTQ arguments are accepted for the uniform optional-module
interface but are not reprocessed.
EOF
}

SAMPLE=""
READ_LAYOUT=""
READ1=""
READ2=""
OUTPUT_DIR=""
ASSEMBLY=""
DB_ROOT=""
THREADS=8

while (( $# > 0 )); do
    case "$1" in
        --sample)
            [[ $# -ge 2 ]] || die "--sample requires a value"
            SAMPLE="$2"
            shift 2
            ;;
        --layout)
            [[ $# -ge 2 ]] || die "--layout requires a value"
            READ_LAYOUT="${2,,}"
            shift 2
            ;;
        --read1)
            [[ $# -ge 2 ]] || die "--read1 requires a value"
            READ1="$2"
            shift 2
            ;;
        --read2)
            [[ $# -ge 2 ]] || die "--read2 requires a value"
            READ2="$2"
            shift 2
            ;;
        --output-dir)
            [[ $# -ge 2 ]] || die "--output-dir requires a value"
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --assembly)
            [[ $# -ge 2 ]] || die "--assembly requires a value"
            ASSEMBLY="$2"
            shift 2
            ;;
        --db-root)
            [[ $# -ge 2 ]] || die "--db-root requires a value"
            DB_ROOT="$2"
            shift 2
            ;;
        --threads)
            [[ $# -ge 2 ]] || die "--threads requires a value"
            THREADS="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "Unknown argument: $1"
            ;;
    esac
done

[[ -n "$SAMPLE" ]] || die "--sample is required"
[[ "$READ_LAYOUT" == "single" || "$READ_LAYOUT" == "paired" ]] ||
    die "--layout must be single or paired"
[[ -s "$READ1" ]] || die "--read1 is missing or empty: $READ1"
if [[ "$READ_LAYOUT" == "paired" ]]; then
    [[ -s "$READ2" ]] || die "--read2 is missing or empty: $READ2"
fi
[[ -n "$OUTPUT_DIR" ]] || die "--output-dir is required"
[[ "$ASSEMBLY" == "GRCh37" || "$ASSEMBLY" == "GRCh38" ]] ||
    die "--assembly must resolve to GRCh37 or GRCh38"
[[ -d "$DB_ROOT" ]] || die "--db-root was not found: $DB_ROOT"
[[ "$THREADS" =~ ^[1-9][0-9]*$ ]] ||
    die "--threads must be a positive integer"

MODULE_CONFIG="${DB_ROOT}/shared/isoforms_module/config/${ASSEMBLY}.config"
[[ -s "$MODULE_CONFIG" ]] ||
    die "Isoforms module is not installed for $ASSEMBLY: $MODULE_CONFIG"

# shellcheck disable=SC1090
source "$MODULE_CONFIG"

[[ "${ISOFORMS_ASSEMBLY:-}" == "$ASSEMBLY" ]] ||
    die "Isoforms configuration is not for $ASSEMBLY"
[[ -n "${ISOFORMS_CONDA_ENV:-}" ]] ||
    die "Isoforms configuration does not define ISOFORMS_CONDA_ENV"
[[ "${CONDA_DEFAULT_ENV:-}" == "$ISOFORMS_CONDA_ENV" ]] ||
    die "Conda environment '$ISOFORMS_CONDA_ENV' is not active"

SAMPLE_RESULTS_DIR="$(dirname -- "$(dirname -- "$OUTPUT_DIR")")"
RSEM_ISOFORMS="${SAMPLE_RESULTS_DIR}/rsem/${SAMPLE}.isoforms.results"
[[ -s "$RSEM_ISOFORMS" ]] ||
    die "Core RSEM isoform results are missing: $RSEM_ISOFORMS"

mkdir -p "$OUTPUT_DIR"
printf 'sample\trsem_isoforms\n%s\t%s\n' \
    "$SAMPLE" \
    "$RSEM_ISOFORMS" \
    > "${OUTPUT_DIR}/input_manifest.tsv"
