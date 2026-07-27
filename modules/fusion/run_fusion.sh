#!/usr/bin/env bash

set -Eeuo pipefail

log_info() {
    printf '[fusion] %s\n' "$*"
}

die() {
    printf '[fusion] ERROR: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage:
  run_fusion.sh --sample SAMPLE --layout single|paired --read1 R1.fastq.gz \
    [--read2 R2.fastq.gz] --output-dir DIR --ctat-genome-lib DIR [options]

Required:
  --sample ID                 Sample identifier
  --layout TYPE               Sequencing layout: single or paired
  --read1 FILE                Trimmed single-end read or paired-end R1 FASTQ
  --output-dir DIR            Destination directory for this sample
  --ctat-genome-lib DIR       CTAT genome library build directory

Options:
  --read2 FILE                Trimmed R2 FASTQ; required for paired layout
  --caller NAME               both, star-fusion, or arriba; default: both
  --threads N                 Worker threads; default: 8
  --arriba-blacklist FILE     Assembly-matched Arriba blacklist
  --arriba-known-fusions FILE Assembly-matched known-fusions database
  --arriba-protein-domains FILE
                              Assembly-matched protein-domain database
  --star-fusion-executable FILE
                              STAR-Fusion executable; default: search PATH
  --keep-arriba-bam           Retain Arriba's intermediate chimeric BAM
  -h, --help                  Show this help

The CTAT library must contain ref_genome.fa, ref_annot.gtf, and
ref_genome.fa.star.idx. Arriba database files are optional but strongly
recommended. They must match the selected reference assembly.
EOF
}

require_file() {
    [[ -s "$1" ]] || die "Required file is missing or empty: $1"
}

require_directory() {
    [[ -d "$1" ]] || die "Required directory was not found: $1"
}

require_command() {
    command -v "$1" >/dev/null 2>&1 ||
        die "Required command was not found in PATH: $1"
}

SAMPLE=""
READ_LAYOUT=""
READ1=""
READ2=""
OUTPUT_DIR=""
CTAT_GENOME_LIB=""
CALLER="both"
THREADS=8
ARRIBA_BLACKLIST=""
ARRIBA_KNOWN_FUSIONS=""
ARRIBA_PROTEIN_DOMAINS=""
STAR_FUSION_EXECUTABLE="STAR-Fusion"
KEEP_ARRIBA_BAM=false

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
        --ctat-genome-lib)
            [[ $# -ge 2 ]] || die "--ctat-genome-lib requires a value"
            CTAT_GENOME_LIB="$2"
            shift 2
            ;;
        --caller)
            [[ $# -ge 2 ]] || die "--caller requires a value"
            CALLER="${2,,}"
            shift 2
            ;;
        --threads)
            [[ $# -ge 2 ]] || die "--threads requires a value"
            THREADS="$2"
            shift 2
            ;;
        --arriba-blacklist)
            [[ $# -ge 2 ]] || die "--arriba-blacklist requires a value"
            ARRIBA_BLACKLIST="$2"
            shift 2
            ;;
        --arriba-known-fusions)
            [[ $# -ge 2 ]] || die "--arriba-known-fusions requires a value"
            ARRIBA_KNOWN_FUSIONS="$2"
            shift 2
            ;;
        --arriba-protein-domains)
            [[ $# -ge 2 ]] || die "--arriba-protein-domains requires a value"
            ARRIBA_PROTEIN_DOMAINS="$2"
            shift 2
            ;;
        --star-fusion-executable)
            [[ $# -ge 2 ]] || die "--star-fusion-executable requires a value"
            STAR_FUSION_EXECUTABLE="$2"
            shift 2
            ;;
        --keep-arriba-bam)
            KEEP_ARRIBA_BAM=true
            shift
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
[[ "$SAMPLE" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] ||
    die "Invalid sample identifier: $SAMPLE"
[[ "$READ_LAYOUT" == "single" || "$READ_LAYOUT" == "paired" ]] ||
    die "--layout must be single or paired"
[[ -n "$READ1" ]] || die "--read1 is required"
if [[ "$READ_LAYOUT" == "paired" ]]; then
    [[ -n "$READ2" ]] || die "--read2 is required for paired layout"
fi
[[ -n "$OUTPUT_DIR" ]] || die "--output-dir is required"
[[ -n "$CTAT_GENOME_LIB" ]] || die "--ctat-genome-lib is required"
[[ "$THREADS" =~ ^[1-9][0-9]*$ ]] ||
    die "--threads must be a positive integer"
[[ "$CALLER" == "both" || "$CALLER" == "star-fusion" || "$CALLER" == "arriba" ]] ||
    die "--caller must be both, star-fusion, or arriba"

require_file "$READ1"
if [[ "$READ_LAYOUT" == "paired" ]]; then
    require_file "$READ2"
fi
require_directory "$CTAT_GENOME_LIB"

REFERENCE_FASTA="${CTAT_GENOME_LIB}/ref_genome.fa"
REFERENCE_GTF="${CTAT_GENOME_LIB}/ref_annot.gtf"
STAR_INDEX="${CTAT_GENOME_LIB}/ref_genome.fa.star.idx"

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd -- "$OUTPUT_DIR" && pwd -P)"

run_star_fusion() {
    local caller_dir="${OUTPUT_DIR}/star-fusion"
    local predictions="${caller_dir}/star-fusion.fusion_predictions.tsv"
    local sample_predictions="${caller_dir}/${SAMPLE}.star-fusion.fusion_genes.tsv"
    local -a read_arguments

    if [[ "$STAR_FUSION_EXECUTABLE" == */* ]]; then
        [[ -x "$STAR_FUSION_EXECUTABLE" ]] ||
            die "STAR-Fusion executable was not found: $STAR_FUSION_EXECUTABLE"
    else
        require_command "$STAR_FUSION_EXECUTABLE"
    fi
    require_command perl
    perl -MDB_File -e 'exit 0' 2>/dev/null ||
        die "STAR-Fusion requires Perl DB_File. Repair it with: ./install_pipe.sh --add-modules fusion --assembly GRCh38 (or GRCh37)"
    if [[ "$STAR_FUSION_EXECUTABLE" == */* ]]; then
        local star_fusion_root
        star_fusion_root="$(cd -- "$(dirname -- "$STAR_FUSION_EXECUTABLE")" && pwd -P)"
        PERL5LIB="${star_fusion_root}/PerlLib${PERL5LIB:+:${PERL5LIB}}" \
            perl -MSet::IntervalTree -e 'exit 0' 2>/dev/null ||
            die "STAR-Fusion's Set::IntervalTree extension does not match the active Perl. Repair the fusion installation before retrying."
    fi
    mkdir -p "$caller_dir"

    if [[ "$READ_LAYOUT" == "paired" ]]; then
        read_arguments=(--left_fq "$READ1" --right_fq "$READ2")
    else
        read_arguments=(--left_fq "$READ1")
    fi

    log_info "Running STAR-Fusion for $SAMPLE"
    "$STAR_FUSION_EXECUTABLE" \
        --CPU "$THREADS" \
        --genome_lib_dir "$CTAT_GENOME_LIB" \
        "${read_arguments[@]}" \
        --output_dir "$caller_dir"

    require_file "$predictions"

    awk -v sample="$SAMPLE" 'BEGIN { FS=OFS="\t" }
        NR == 1 { sub(/^#/, "", $0); print "Sample", $0; next }
        { print sample, $0 }
    ' "$predictions" > "$sample_predictions"

    require_file "$sample_predictions"
}

run_arriba() {
    local caller_dir="${OUTPUT_DIR}/arriba"
    local star_prefix="${caller_dir}/${SAMPLE}."
    local star_tmp="${caller_dir}/STAR_tmp"
    local chimeric_bam="${star_prefix}Aligned.out.bam"
    local fusions="${caller_dir}/fusions.tsv"
    local discarded="${caller_dir}/fusions.discarded.tsv"
    local sample_fusions="${caller_dir}/${SAMPLE}.arriba.fusion_genes.tsv"
    local -a arriba_arguments
    local -a star_layout_arguments
    local -a star_read_arguments

    require_command STAR
    require_command arriba
    require_file "$REFERENCE_FASTA"
    require_file "$REFERENCE_GTF"
    require_directory "$STAR_INDEX"

    [[ -z "$ARRIBA_BLACKLIST" ]] || require_file "$ARRIBA_BLACKLIST"
    [[ -z "$ARRIBA_KNOWN_FUSIONS" ]] || require_file "$ARRIBA_KNOWN_FUSIONS"
    [[ -z "$ARRIBA_PROTEIN_DOMAINS" ]] || require_file "$ARRIBA_PROTEIN_DOMAINS"

    mkdir -p "$caller_dir"

    star_read_arguments=("$READ1")
    if [[ "$READ_LAYOUT" == "paired" ]]; then
        star_read_arguments+=("$READ2")
        star_layout_arguments=(
            --peOverlapNbasesMin 10
            --alignSplicedMateMapLminOverLmate 0.5
        )
    else
        star_layout_arguments=()
    fi

    log_info "Generating an Arriba-compatible STAR alignment for $SAMPLE"
    STAR \
        --runThreadN "$THREADS" \
        --genomeLoad NoSharedMemory \
        --genomeDir "$STAR_INDEX" \
        --readFilesIn "${star_read_arguments[@]}" \
        --readFilesCommand zcat \
        --outSAMtype BAM Unsorted \
        --outSAMunmapped Within \
        --outBAMcompression 0 \
        --outFilterMultimapNmax 50 \
        "${star_layout_arguments[@]}" \
        --alignSJstitchMismatchNmax 5 -1 5 5 \
        --chimSegmentMin 10 \
        --chimOutType WithinBAM HardClip \
        --chimJunctionOverhangMin 10 \
        --chimScoreDropMax 30 \
        --chimScoreJunctionNonGTAG 0 \
        --chimScoreSeparation 1 \
        --chimSegmentReadGapMax 3 \
        --chimMultimapNmax 50 \
        --outSAMattrRGline "ID:${SAMPLE}" "SM:${SAMPLE}" "LB:${SAMPLE}" "PL:illumina" \
        --outTmpDir "$star_tmp" \
        --outFileNamePrefix "$star_prefix"

    require_file "$chimeric_bam"

    arriba_arguments=(
        -x "$chimeric_bam"
        -o "$fusions"
        -O "$discarded"
        -a "$REFERENCE_FASTA"
        -g "$REFERENCE_GTF"
    )
    [[ -z "$ARRIBA_BLACKLIST" ]] ||
        arriba_arguments+=(-b "$ARRIBA_BLACKLIST")
    [[ -z "$ARRIBA_KNOWN_FUSIONS" ]] ||
        arriba_arguments+=(-k "$ARRIBA_KNOWN_FUSIONS")
    [[ -z "$ARRIBA_PROTEIN_DOMAINS" ]] ||
        arriba_arguments+=(-p "$ARRIBA_PROTEIN_DOMAINS")

    log_info "Running Arriba for $SAMPLE"
    arriba "${arriba_arguments[@]}"
    require_file "$fusions"

    awk -v sample="$SAMPLE" 'BEGIN { FS=OFS="\t" }
        NR == 1 { sub(/^#/, "", $0); print "Sample", $0; next }
        { print sample, $0 }
    ' "$fusions" > "$sample_fusions"

    require_file "$sample_fusions"

    if [[ "$KEEP_ARRIBA_BAM" != true ]]; then
        rm -f -- "$chimeric_bam"
    fi
    rm -rf -- "$star_tmp"
}

case "$CALLER" in
    both)
        run_star_fusion
        run_arriba
        ;;
    star-fusion)
        run_star_fusion
        ;;
    arriba)
        run_arriba
        ;;
esac

log_info "Fusion detection completed for $SAMPLE: $OUTPUT_DIR"
