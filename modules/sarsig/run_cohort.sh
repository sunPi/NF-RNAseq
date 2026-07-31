#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
MATRIX_DIR=""; OUTPUT_DIR=""; SAMPLES_FILE=""; DB_ROOT=""; ASSEMBLY=""
DESIGN=""; CONTRASTS_FILE=""; THREADS=1
die() { printf '[sarsig] ERROR: %s\n' "$*" >&2; exit 1; }
while (( $# )); do case "$1" in
    --matrix-dir) MATRIX_DIR="$2"; shift 2;; --output-dir) OUTPUT_DIR="$2"; shift 2;;
    --samples-file) SAMPLES_FILE="$2"; shift 2;; --db-root) DB_ROOT="$2"; shift 2;;
    --assembly) ASSEMBLY="$2"; shift 2;; --threads) THREADS="$2"; shift 2;;
    --design) DESIGN="$2"; shift 2;; --contrasts-file) CONTRASTS_FILE="$2"; shift 2;;
    --results-dir|--contrast) shift 2;; *) die "Unknown argument: $1";; esac; done
EXPRESSION="${MATRIX_DIR}/annotated/deduplicated/gene_TPM.highest.tsv"
[[ -s "$EXPRESSION" ]] || die "Annotated deduplicated TPM matrix not found: $EXPRESSION"
[[ -s "$SAMPLES_FILE" ]] || die "QC-included sample list not found: $SAMPLES_FILE"
CONFIG="${DB_ROOT}/shared/sarsig_module/config/${ASSEMBLY}.config"
[[ -s "$CONFIG" ]] || die "SarSig is not installed for $ASSEMBLY: $CONFIG"
# shellcheck disable=SC1090
source "$CONFIG"
[[ -s "${SARSIG_SIGNATURE:-}" ]] || die "Configured SarSig signature was not found"
arguments=(--expression "$EXPRESSION" --samples-file "$SAMPLES_FILE"
    --signature "$SARSIG_SIGNATURE" --signature-sha256 "$SARSIG_SIGNATURE_SHA256"
    --output-dir "$OUTPUT_DIR")
[[ -z "$DESIGN" ]] || arguments+=(--design "$DESIGN" --contrasts "$CONTRASTS_FILE")
mkdir -p "$OUTPUT_DIR"
exec conda run --name "$SARSIG_CONDA_ENV" Rscript "${SCRIPT_DIR}/run_sarsig.R" "${arguments[@]}"
