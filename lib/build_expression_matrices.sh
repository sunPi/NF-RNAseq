#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
RESULTS_DIR=""
SAMPLES_FILE=""
GENE_ANNOTATION=""

die() {
    printf '[matrices] ERROR: %s\n' "$*" >&2
    exit 1
}

while (( $# > 0 )); do
    case "$1" in
        --results-dir) RESULTS_DIR="$2"; shift 2 ;;
        --samples-file) SAMPLES_FILE="$2"; shift 2 ;;
        --gene-annotation) GENE_ANNOTATION="$2"; shift 2 ;;
        *) die "Unknown argument: $1" ;;
    esac
done

[[ -d "$RESULTS_DIR" ]] || die "Results directory not found: $RESULTS_DIR"
[[ -s "$SAMPLES_FILE" ]] || die "QC-included sample list not found: $SAMPLES_FILE"
[[ -s "$GENE_ANNOTATION" ]] || die "Gene annotation not found: $GENE_ANNOTATION"

mapfile -t SAMPLES < "$SAMPLES_FILE"
(( ${#SAMPLES[@]} > 0 )) || die "QC-included sample list is empty"

MATRIX_DIR="${RESULTS_DIR}/matrices"
EXPRESSION_MATRIX_DIR="${MATRIX_DIR}/expression"
ANNOTATED_MATRIX_DIR="${MATRIX_DIR}/annotated"
DEDUPLICATED_MATRIX_DIR="${ANNOTATED_MATRIX_DIR}/deduplicated"
mkdir -p "$EXPRESSION_MATRIX_DIR" "$ANNOTATED_MATRIX_DIR" "$DEDUPLICATED_MATRIX_DIR"

RAW_COUNTS_MATRIX="${EXPRESSION_MATRIX_DIR}/gene_counts.tsv"
RSEM_COUNTS_MATRIX="${EXPRESSION_MATRIX_DIR}/gene_rsem_expected_counts.tsv"
RAW_TPM_MATRIX="${EXPRESSION_MATRIX_DIR}/gene_TPM.tsv"
RAW_FPKM_MATRIX="${EXPRESSION_MATRIX_DIR}/gene_FPKM.tsv"
COUNTS_MATRIX="${ANNOTATED_MATRIX_DIR}/gene_counts.tsv"
TPM_MATRIX="${ANNOTATED_MATRIX_DIR}/gene_TPM.tsv"
FPKM_MATRIX="${ANNOTATED_MATRIX_DIR}/gene_FPKM.tsv"
SYMBOL_COUNTS_MATRIX="${DEDUPLICATED_MATRIX_DIR}/gene_counts.highest.tsv"
SYMBOL_TPM_MATRIX="${DEDUPLICATED_MATRIX_DIR}/gene_TPM.highest.tsv"
SYMBOL_FPKM_MATRIX="${DEDUPLICATED_MATRIX_DIR}/gene_FPKM.highest.tsv"
MATRIX_MANIFEST="${MATRIX_DIR}/matrix_manifest.tsv"

GENE_RESULT_FILES=()
for sample in "${SAMPLES[@]}"; do
    result_file="${RESULTS_DIR}/${sample}/rsem/${sample}.genes.results"
    [[ -s "$result_file" ]] ||
        die "RSEM gene result file is missing or empty: $result_file"
    GENE_RESULT_FILES+=("$result_file")
done

generate_rsem_matrix() {
    local column_number="$1"
    local output_file="$2"
    local temporary_dir
    local index
    local sample
    local value_file
    local -a value_files=()

    temporary_dir="$(mktemp -d "${MATRIX_DIR}/.matrix_tmp.XXXXXX")" ||
        die "Could not create a temporary matrix directory"

    cut -f1 "${GENE_RESULT_FILES[0]}" | tail -n +2 > "${temporary_dir}/gene_ids"
    for index in "${!SAMPLES[@]}"; do
        value_file="${temporary_dir}/${index}.values"
        cut -f"$column_number" "${GENE_RESULT_FILES[$index]}" |
            tail -n +2 > "$value_file"
        value_files+=("$value_file")
    done

    {
        printf 'gene_id'
        for sample in "${SAMPLES[@]}"; do
            printf '\t%s' "$sample"
        done
        printf '\n'
        paste "${temporary_dir}/gene_ids" "${value_files[@]}"
    } > "$output_file"

    rm -rf -- "$temporary_dir"
    [[ -s "$output_file" ]] || die "Could not generate matrix: $output_file"
}

generate_featurecounts_matrix() {
    local output_file="$1"
    local temporary_dir
    local index
    local sample
    local result_file
    local value_file
    local -a value_files=()

    temporary_dir="$(mktemp -d "${MATRIX_DIR}/.featurecounts_tmp.XXXXXX")" ||
        die "Could not create a FeatureCounts matrix temporary directory"

    for index in "${!SAMPLES[@]}"; do
        sample="${SAMPLES[$index]}"
        result_file="${RESULTS_DIR}/${sample}/featurecounts/${sample}.featureCounts.tsv"
        [[ -s "$result_file" ]] ||
            die "FeatureCounts result is missing or empty: $result_file"
        cut -f1 "$result_file" | tail -n +3 > "${temporary_dir}/${index}.ids"
        value_file="${temporary_dir}/${index}.values"
        cut -f7 "$result_file" | tail -n +3 > "$value_file"
        if (( index > 0 )) &&
           ! cmp -s "${temporary_dir}/0.ids" "${temporary_dir}/${index}.ids"; then
            rm -rf -- "$temporary_dir"
            die "FeatureCounts gene order differs for sample: $sample"
        fi
        if ! awk '/^[0-9]+$/ {next} {exit 1}' "$value_file"; then
            rm -rf -- "$temporary_dir"
            die "FeatureCounts produced a non-integer value for sample: $sample"
        fi
        value_files+=("$value_file")
    done

    {
        printf 'gene_id'
        for sample in "${SAMPLES[@]}"; do
            printf '\t%s' "$sample"
        done
        printf '\n'
        paste "${temporary_dir}/0.ids" "${value_files[@]}"
    } > "$output_file"

    rm -rf -- "$temporary_dir"
    [[ -s "$output_file" ]] || die "Could not generate matrix: $output_file"
}

printf '[matrices] Generating integer FeatureCounts matrix\n'
generate_featurecounts_matrix "$RAW_COUNTS_MATRIX"
printf '[matrices] Generating RSEM expected-count, TPM, and FPKM matrices\n'
generate_rsem_matrix 5 "$RSEM_COUNTS_MATRIX"
generate_rsem_matrix 6 "$RAW_TPM_MATRIX"
generate_rsem_matrix 7 "$RAW_FPKM_MATRIX"

printf '[matrices] Annotating gene matrices\n'
python3 "${SCRIPT_DIR}/map_gene_ids.py" \
    --input "$RAW_COUNTS_MATRIX" --mapping "$GENE_ANNOTATION" --output "$COUNTS_MATRIX"
python3 "${SCRIPT_DIR}/map_gene_ids.py" \
    --input "$RAW_TPM_MATRIX" --mapping "$GENE_ANNOTATION" --output "$TPM_MATRIX"
python3 "${SCRIPT_DIR}/map_gene_ids.py" \
    --input "$RAW_FPKM_MATRIX" --mapping "$GENE_ANNOTATION" --output "$FPKM_MATRIX"

printf '[matrices] Resolving duplicate symbols using highest total expression\n'
Rscript "${SCRIPT_DIR}/handle_gene_dups.R" \
    --input "$COUNTS_MATRIX" --output "$SYMBOL_COUNTS_MATRIX" --strategy highest
Rscript "${SCRIPT_DIR}/handle_gene_dups.R" \
    --input "$TPM_MATRIX" --output "$SYMBOL_TPM_MATRIX" --strategy highest
Rscript "${SCRIPT_DIR}/handle_gene_dups.R" \
    --input "$FPKM_MATRIX" --output "$SYMBOL_FPKM_MATRIX" --strategy highest

{
    printf 'matrix_id\tquantifier\tvalue_type\tannotation\tduplicate_symbols\tpath\n'
    printf 'gene_counts\tfeatureCounts\tinteger\tgene_id\tretained\t%s\n' "$RAW_COUNTS_MATRIX"
    printf 'gene_rsem_expected_counts\tRSEM\tcontinuous\tgene_id\tretained\t%s\n' "$RSEM_COUNTS_MATRIX"
    printf 'gene_TPM\tRSEM\tcontinuous\tgene_id\tretained\t%s\n' "$RAW_TPM_MATRIX"
    printf 'gene_FPKM\tRSEM\tcontinuous\tgene_id\tretained\t%s\n' "$RAW_FPKM_MATRIX"
    printf 'annotated_gene_counts\tfeatureCounts\tinteger\tgene_id,gene_name,gene_type\tretained\t%s\n' "$COUNTS_MATRIX"
    printf 'annotated_gene_TPM\tRSEM\tcontinuous\tgene_id,gene_name,gene_type\tretained\t%s\n' "$TPM_MATRIX"
    printf 'annotated_gene_FPKM\tRSEM\tcontinuous\tgene_id,gene_name,gene_type\tretained\t%s\n' "$FPKM_MATRIX"
    printf 'symbol_gene_counts\tfeatureCounts\tinteger\tgene_id,gene_name,gene_type\thighest\t%s\n' "$SYMBOL_COUNTS_MATRIX"
    printf 'symbol_gene_TPM\tRSEM\tcontinuous\tgene_id,gene_name,gene_type\thighest\t%s\n' "$SYMBOL_TPM_MATRIX"
    printf 'symbol_gene_FPKM\tRSEM\tcontinuous\tgene_id,gene_name,gene_type\thighest\t%s\n' "$SYMBOL_FPKM_MATRIX"
} > "$MATRIX_MANIFEST"

printf '[matrices] Completed: %s\n' "$MATRIX_MANIFEST"
