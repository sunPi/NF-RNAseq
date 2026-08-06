#!/usr/bin/env bash
set -Eeuo pipefail

die() { printf '[trust4] ERROR: %s\n' "$*" >&2; exit 1; }

SAMPLE=""; READ_LAYOUT=""; READ1=""; READ2=""; OUTPUT_DIR=""
ASSEMBLY=""; DB_ROOT=""; THREADS=8
while (( $# )); do
    case "$1" in
        --sample) SAMPLE="$2"; shift 2 ;;
        --layout) READ_LAYOUT="${2,,}"; shift 2 ;;
        --read1) READ1="$2"; shift 2 ;;
        --read2) READ2="$2"; shift 2 ;;
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        --assembly) ASSEMBLY="$2"; shift 2 ;;
        --db-root) DB_ROOT="$2"; shift 2 ;;
        --threads) THREADS="$2"; shift 2 ;;
        -h|--help)
            printf 'Usage: run_module.sh --sample ID --layout single|paired --read1 FILE [--read2 FILE] --output-dir DIR --assembly GRCh37|GRCh38 --db-root DIR [--threads N]\n'
            exit 0 ;;
        *) die "Unknown argument: $1" ;;
    esac
done

[[ "$SAMPLE" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "Invalid --sample"
[[ "$READ_LAYOUT" == single || "$READ_LAYOUT" == paired ]] || die "Invalid --layout"
[[ -s "$READ1" ]] || die "R1 is missing or empty: $READ1"
[[ "$READ_LAYOUT" != paired || -s "$READ2" ]] || die "R2 is missing or empty: $READ2"
[[ -n "$OUTPUT_DIR" && -d "$DB_ROOT" ]] || die "--output-dir and --db-root are required"
[[ "$ASSEMBLY" == GRCh37 || "$ASSEMBLY" == GRCh38 ]] || die "Invalid --assembly"
[[ "$THREADS" =~ ^[1-9][0-9]*$ ]] || die "--threads must be positive"

MODULE_CONFIG="$DB_ROOT/shared/trust4_module/config/${ASSEMBLY}.config"
[[ -s "$MODULE_CONFIG" ]] || die "TRUST4 is not installed for $ASSEMBLY"
# shellcheck disable=SC1090
source "$MODULE_CONFIG"
[[ -x "$TRUST4_EXECUTABLE" ]] || die "TRUST4 executable is missing: $TRUST4_EXECUTABLE"
[[ -s "$TRUST4_VDJC_REFERENCE" ]] || die "V(D)J reference is missing"
[[ -s "$TRUST4_IMGT_REFERENCE" ]] || die "IMGT reference is missing"

mkdir -p "$OUTPUT_DIR"
arguments=(
    -f "$TRUST4_VDJC_REFERENCE"
    --ref "$TRUST4_IMGT_REFERENCE"
    -o "$SAMPLE"
    --od "$OUTPUT_DIR"
    -t "$THREADS"
    --clean 1
)
if [[ "$READ_LAYOUT" == paired ]]; then
    arguments+=(-1 "$READ1" -2 "$READ2")
else
    arguments+=(-u "$READ1")
fi

"$TRUST4_EXECUTABLE" "${arguments[@]}" \
    > "$OUTPUT_DIR/${SAMPLE}.stdout.log" \
    2> "$OUTPUT_DIR/${SAMPLE}.stderr.log"

for output in "${SAMPLE}_report.tsv" "${SAMPLE}_airr.tsv"; do
    [[ -s "$OUTPUT_DIR/$output" ]] || die "Expected output is missing: $OUTPUT_DIR/$output"
done
printf '[trust4] Completed: %s\n' "$OUTPUT_DIR"
