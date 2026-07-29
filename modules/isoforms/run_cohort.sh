#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
RESULTS_DIR=""
OUTPUT_DIR=""
SAMPLES_FILE=""

while (( $# > 0 )); do
    case "$1" in
        --results-dir)
            RESULTS_DIR="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --samples-file)
            SAMPLES_FILE="$2"
            shift 2
            ;;
        --matrix-dir|--assembly|--db-root|--threads|--design|--contrasts-file)
            shift 2
            ;;
        --contrast)
            shift 2
            ;;
        *)
            printf '[isoforms] ERROR: Unknown argument: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

[[ -d "$RESULTS_DIR" ]] || {
    printf '[isoforms] ERROR: Results directory not found: %s\n' "$RESULTS_DIR" >&2
    exit 1
}
[[ -s "$SAMPLES_FILE" ]] || {
    printf '[isoforms] ERROR: Sample list not found: %s\n' "$SAMPLES_FILE" >&2
    exit 1
}
[[ -n "$OUTPUT_DIR" ]] || {
    printf '[isoforms] ERROR: --output-dir is required\n' >&2
    exit 1
}

exec python3 "${SCRIPT_DIR}/aggregate_module.py" \
    --results-dir "$RESULTS_DIR" \
    --output-dir "$OUTPUT_DIR" \
    --samples-file "$SAMPLES_FILE"
