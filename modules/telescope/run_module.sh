#!/usr/bin/env bash
set -Eeuo pipefail

die() { printf '[telescope] ERROR: %s\n' "$*" >&2; exit 1; }

SAMPLE=""; BAM=""; OUTPUT_DIR=""; ASSEMBLY=""; DB_ROOT=""; THREADS=1
while (( $# )); do
    case "$1" in
        --sample) SAMPLE="$2"; shift 2 ;;
        --bam) BAM="$2"; shift 2 ;;
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        --assembly) ASSEMBLY="$2"; shift 2 ;;
        --db-root) DB_ROOT="$2"; shift 2 ;;
        --threads) THREADS="$2"; shift 2 ;;
        --layout|--read1|--read2) shift 2 ;;
        -h|--help)
            printf 'Usage: run_module.sh --sample ID --bam FILE --output-dir DIR --assembly GRCh37|GRCh38 --db-root DIR [--threads N]\n'
            exit 0 ;;
        *) die "Unknown argument: $1" ;;
    esac
done

[[ "$SAMPLE" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "Invalid --sample"
[[ -s "$BAM" ]] || die "Core genomic BAM is missing or empty: $BAM"
[[ -n "$OUTPUT_DIR" && -d "$DB_ROOT" ]] || die "--output-dir and --db-root are required"
[[ "$ASSEMBLY" == GRCh37 || "$ASSEMBLY" == GRCh38 ]] || die "Invalid --assembly"
[[ "$THREADS" =~ ^[1-9][0-9]*$ ]] || die "--threads must be positive"

MODULE_CONFIG="$DB_ROOT/shared/telescope_module/config/${ASSEMBLY}.config"
[[ -s "$MODULE_CONFIG" ]] || die "Telescope is not installed for $ASSEMBLY"
# shellcheck disable=SC1090
source "$MODULE_CONFIG"
[[ -x "$TELESCOPE_EXECUTABLE" ]] || die "Telescope executable is missing"
[[ -s "$TELESCOPE_ANNOTATION" ]] || die "Telescope annotation is missing"
command -v conda >/dev/null 2>&1 || die "conda is required"
command -v samtools >/dev/null 2>&1 || die "samtools is required"

mkdir -p "$OUTPUT_DIR"
COLLATED_BAM="$OUTPUT_DIR/${SAMPLE}.name_collated.bam"
samtools collate -@ "$THREADS" -O -u "$BAM" > "$COLLATED_BAM"
[[ -s "$COLLATED_BAM" ]] || die "samtools collate produced no BAM"

conda run --name "$TELESCOPE_CONDA_ENV" \
    "$TELESCOPE_EXECUTABLE" assign \
    --outdir "$OUTPUT_DIR" \
    --exp_tag "$SAMPLE" \
    --reassign_mode exclude \
    "$COLLATED_BAM" "$TELESCOPE_ANNOTATION" \
    > "$OUTPUT_DIR/${SAMPLE}.stdout.log" \
    2> "$OUTPUT_DIR/${SAMPLE}.stderr.log"

[[ -s "$OUTPUT_DIR/${SAMPLE}-TE_counts.tsv" ]] ||
    die "Telescope count output is missing"
[[ -s "$OUTPUT_DIR/${SAMPLE}-run_stats.tsv" ]] ||
    die "Telescope statistics output is missing"
rm -f -- "$COLLATED_BAM"
printf '[telescope] Completed: %s\n' "$OUTPUT_DIR"
