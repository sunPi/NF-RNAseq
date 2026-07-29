#!/usr/bin/env bash

set -Eeuo pipefail

################################################################################
# 0. Preprocessing commands
################################################################################

if [[ "${1:-}" == "prepare-samples" ]]; then
    shift

    SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
    SAMPLESHEET_GENERATOR="${SCRIPT_DIR}/setup/scripts/create_samplesheet.py"

    [[ -f "$SAMPLESHEET_GENERATOR" ]] || {
        printf '[ERROR] Sample-sheet generator not found: %s\n' \
            "$SAMPLESHEET_GENERATOR" >&2
        exit 1
    }

    command -v python3 >/dev/null 2>&1 || {
        printf '[ERROR] python3 is required to prepare a sample sheet.\n' >&2
        exit 1
    }

    exec python3 "$SAMPLESHEET_GENERATOR" "$@"
fi

################################################################################
# 1. Command helpers and usage
################################################################################

ORIGINAL_ARGUMENTS=("$@")

log_info() {
    printf '[INFO] %s\n' "$*"
}

log_error() {
    printf '[ERROR] %s\n' "$*" >&2
}

die() {
    log_error "$*"
    exit 1
}

usage() {
    cat <<EOF
Usage:
  $(basename "$0") --assembly <ASSEMBLY> --layout <single|paired> \\
    --experiment <PATH> --input <DIRECTORY> [--pipeline core|optional] \\
    [--modules all|MODULE[,MODULE...]] [--design FILE] \\
    [--contrast FACTOR:NUMERATOR:DENOMINATOR]

  $(basename "$0") --assembly <ASSEMBLY> --layout <single|paired> \\
    --experiment <PATH> --pipeline modules \\
    [--modules all|MODULE[,MODULE...]]

  $(basename "$0") prepare-samples --input <DIRECTORY> \\
    --layout <single|paired> --output <SAMPLESHEET.csv>

Options:
  -a, --assembly NAME    Reference assembly: GRCh37, hg19, GRCh38, or hg38
  -l, --layout TYPE      Sequencing layout: single or paired
  -e, --experiment PATH  Experiment path used under results/PATH
  -i, --input DIRECTORY  Directory containing FASTQ files; searched recursively
  -p, --pipeline MODE    core, optional, or modules; default: core
  -m, --modules VALUE    all or a comma-separated optional-module list
  -d, --design FILE      Sample metadata TSV/CSV with a required sample column
  -c, --contrast VALUE   FACTOR:NUMERATOR:DENOMINATOR; may be repeated

  -h, --help            Show this help message.

Examples:
  $(basename "$0") prepare-samples --input /data/pilot_fastq \\
    --layout single --output pilot.samplesheet.csv

  $(basename "$0") --assembly GRCh37 --layout paired \\
    --experiment KOKI_TEST/SUBTEST --input test_data/UVM/KOKI
  $(basename "$0") --assembly GRCh38 --layout single \\
    --experiment pilot_run --input /data/pilot_fastq
  $(basename "$0") --assembly GRCh38 --layout single \\
    --experiment pilot_run --input /data/pilot_fastq \\
    --pipeline optional --modules all
  $(basename "$0") --assembly GRCh38 --layout single \\
    --experiment pilot_run --pipeline modules --modules fusion

Paired-end names must be NAME_1.fastq.gz and NAME_2.fastq.gz (or .fq.gz).
Results for each pair are written below results/PATH/NAME/.
The modules mode requires a previously completed core run for the experiment.
EOF
}

################################################################################
# 2. Parse command-line arguments
################################################################################

ASSEMBLY_REQUESTED=""
READ_LAYOUT=""
EXPERIMENT_NAME=""
INPUT_DIR_REQUESTED=""
PIPELINE_MODE="core"
MODULES_REQUESTED=""
DESIGN_FILE=""
CONTRASTS=()

while (( $# > 0 )); do
    case "$1" in
        -a|--assembly)
            [[ $# -ge 2 ]] ||
                die "Missing value after $1"

            ASSEMBLY_REQUESTED="$2"
            shift 2
            ;;

        --assembly=*)
            ASSEMBLY_REQUESTED="${1#*=}"
            shift
            ;;

        -l|--layout)
            [[ $# -ge 2 ]] ||
                die "Missing value after $1"

            READ_LAYOUT="${2,,}"
            shift 2
            ;;

        --layout=*)
            READ_LAYOUT="${1#*=}"
            READ_LAYOUT="${READ_LAYOUT,,}"
            shift
            ;;

        -e|--experiment)
            [[ $# -ge 2 ]] ||
                die "Missing value after $1"

            EXPERIMENT_NAME="$2"
            shift 2
            ;;

        --experiment=*)
            EXPERIMENT_NAME="${1#*=}"
            shift
            ;;

        -i|--input)
            [[ $# -ge 2 ]] ||
                die "Missing value after $1"

            INPUT_DIR_REQUESTED="$2"
            shift 2
            ;;

        --input=*)
            INPUT_DIR_REQUESTED="${1#*=}"
            shift
            ;;

        -p|--pipeline)
            [[ $# -ge 2 ]] ||
                die "Missing value after $1"

            PIPELINE_MODE="${2,,}"
            shift 2
            ;;

        --pipeline=*)
            PIPELINE_MODE="${1#*=}"
            PIPELINE_MODE="${PIPELINE_MODE,,}"
            shift
            ;;

        -m|--modules)
            [[ $# -ge 2 ]] ||
                die "Missing value after $1"

            MODULES_REQUESTED="$2"
            shift 2
            ;;

        --modules=*)
            MODULES_REQUESTED="${1#*=}"
            shift
            ;;

        -d|--design)
            [[ $# -ge 2 ]] || die "Missing value after $1"
            DESIGN_FILE="$2"
            shift 2
            ;;

        --design=*)
            DESIGN_FILE="${1#*=}"
            shift
            ;;

        -c|--contrast)
            [[ $# -ge 2 ]] || die "Missing value after $1"
            CONTRASTS+=("$2")
            shift 2
            ;;

        --contrast=*)
            CONTRASTS+=("${1#*=}")
            shift
            ;;

        -h|--help)
            usage
            exit 0
            ;;

        *)
            die "Unknown argument: $1. Run $(basename "$0") --help"
            ;;
    esac
done

(( ${#CONTRASTS[@]} == 0 )) || [[ -n "$DESIGN_FILE" ]] ||
    die "--contrast requires --design"

[[ -n "$ASSEMBLY_REQUESTED" ]] ||
    die "No reference assembly specified. Use --assembly GRCh37 or --assembly GRCh38"

[[ "$READ_LAYOUT" == "single" || "$READ_LAYOUT" == "paired" ]] ||
    die "Invalid or missing layout. Use --layout single or --layout paired"

[[ -n "$EXPERIMENT_NAME" ]] ||
    die "No experiment name specified. Use --experiment NAME"

case "$PIPELINE_MODE" in
    core)
        [[ -z "$MODULES_REQUESTED" ]] ||
            die "--modules cannot be used with --pipeline core"
        ;;
    optional|full)
        PIPELINE_MODE="optional"
        [[ -n "$MODULES_REQUESTED" ]] || MODULES_REQUESTED="all"
        ;;
    modules)
        [[ -n "$MODULES_REQUESTED" ]] || MODULES_REQUESTED="all"
        ;;
    *)
        die "Invalid pipeline mode '$PIPELINE_MODE'. Use core, optional, or modules"
        ;;
esac

if [[ "$PIPELINE_MODE" == "modules" ]]; then
    [[ -z "$INPUT_DIR_REQUESTED" ]] ||
        die "--input is not used with --pipeline modules; modules use prior core outputs"
else
    [[ -n "$INPUT_DIR_REQUESTED" ]] ||
        die "No FASTQ input directory specified. Use --input DIRECTORY"
fi

[[ "$EXPERIMENT_NAME" != /* && "$EXPERIMENT_NAME" != *//* ]] ||
    die "Invalid experiment path '$EXPERIMENT_NAME'. Use a relative path below results/"

IFS='/' read -r -a EXPERIMENT_PATH_PARTS <<< "$EXPERIMENT_NAME"

for path_part in "${EXPERIMENT_PATH_PARTS[@]}"; do
    [[ "$path_part" != "." &&
       "$path_part" != ".." &&
       "$path_part" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] ||
        die "Invalid experiment path component '$path_part' in '$EXPERIMENT_NAME'"
done

################################################################################
# 3. Resolve locations and load installation configuration
################################################################################

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(pwd -P)"
CONFIG_FILE="${SCRIPT_DIR}/config/main.config"
QC_CONFIG_FILE="${SCRIPT_DIR}/config/qc.config"
QC_VALIDATOR="${SCRIPT_DIR}/modules/qc/qc_validator.py"
DESIGN_VALIDATOR="${SCRIPT_DIR}/lib/design_parser.py"

[[ -f "$CONFIG_FILE" ]] ||
    die "Installation configuration not found: $CONFIG_FILE"

[[ -f "$QC_CONFIG_FILE" ]] ||
    die "QC configuration not found: $QC_CONFIG_FILE"

[[ -f "$QC_VALIDATOR" ]] ||
    die "QC validator not found: $QC_VALIDATOR"

[[ -f "$DESIGN_VALIDATOR" ]] ||
    die "Design validator not found: $DESIGN_VALIDATOR"

# shellcheck disable=SC1090
source "$CONFIG_FILE"

declare -F select_reference_assembly >/dev/null ||
    die "Configuration does not define select_reference_assembly: $CONFIG_FILE"

# Resolve all generic reference variables (STAR_INDEX, GENOME_FASTA, GTF,
# RSEM_REFERENCE, VEP paths, etc.) from the assembly requested on the command
# line. The function also verifies that the selected reference is installed.
select_reference_assembly "$ASSEMBLY_REQUESTED" ||
    die "Reference selection failed for: $ASSEMBLY_REQUESTED"

# Ensure the generated configuration contains the variables required by the
# base pipeline. The ${name+x} form is safe with `set -u`.
REQUIRED_CONFIG_VARIABLES=(
    DB_ROOT
    CONDA_ENV
    THREADS
    SPECIES
    ASSEMBLY_DIR
    STAR_INDEX
    GENOME_FASTA
    GTF
    GENE_ANNOTATION
    RSEM_REFERENCE
    ASSEMBLY
)

for variable_name in "${REQUIRED_CONFIG_VARIABLES[@]}"; do
    [[ -n "${!variable_name+x}" ]] ||
        die "Required configuration variable is missing: $variable_name"

    [[ -n "${!variable_name}" ]] ||
        die "Required configuration variable is empty: $variable_name"
done

################################################################################
# 4. Define project input and output paths
################################################################################

READS_DIR=""
if [[ "$PIPELINE_MODE" != "modules" ]]; then
    if [[ "$INPUT_DIR_REQUESTED" == /* ]]; then
        READS_DIR="$INPUT_DIR_REQUESTED"
    else
        READS_DIR="${ROOT_DIR}/${INPUT_DIR_REQUESTED}"
    fi
fi

RESULTS_ROOT="${ROOT_DIR}/results"
RESULTS_DIR="${RESULTS_ROOT}/${EXPERIMENT_NAME}"
PROJECT_INFO_FILE="${RESULTS_DIR}/project_info.tsv"

MATRIX_DIR="${RESULTS_DIR}/matrices"
QC_DIR="${RESULTS_DIR}/QC"
MULTIQC_DIR="${QC_DIR}/multiqc"
LOG_DIR="${QC_DIR}/logs"
DESIGN_DIR="${RESULTS_DIR}/design"
NORMALIZED_DESIGN=""
CONTRASTS_FILE=""

SELECTED_MODULES=()
declare -A MODULE_SCOPES=()
declare -A MODULE_REQUIRES_DESIGN=()
declare -A MODULE_REQUIRES_CONTRASTS=()
declare -A MODULE_OUTPUT_NAMES=()

resolve_selected_modules() {
    local requested_modules="$1"
    local module_name
    local module_metadata
    local module_config
    local module_scope
    local module_requires_design
    local module_requires_contrasts
    local module_output_name
    local -a requested_list=()
    local -A seen_modules=()

    if [[ "${requested_modules,,}" == "all" ]]; then
        mapfile -t requested_list < <(
            find "${SCRIPT_DIR}/modules" -mindepth 2 -maxdepth 2 \
                -type f -name module.config -printf '%h\n' |
                sed 's#.*/##' |
                sort -u
        )
    else
        IFS=',' read -r -a requested_list <<< "$requested_modules"
    fi

    (( ${#requested_list[@]} > 0 )) ||
        die "No runnable optional modules were found"

    for module_name in "${requested_list[@]}"; do
        module_name="${module_name#"${module_name%%[![:space:]]*}"}"
        module_name="${module_name%"${module_name##*[![:space:]]}"}"
        module_name="${module_name,,}"

        [[ "$module_name" =~ ^[a-z0-9][a-z0-9_-]*$ ]] ||
            die "Invalid optional module name: $module_name"
        [[ -z "${seen_modules[$module_name]+x}" ]] ||
            die "Optional module was requested more than once: $module_name"

        module_config="${DB_ROOT}/shared/${module_name}_module/config/${ASSEMBLY}.config"
        if [[ ! -s "$module_config" ]]; then
            if [[ "${requested_modules,,}" == "all" ]]; then
                log_info "Skipping optional module '$module_name' (not installed for $ASSEMBLY)"
                continue
            fi
            die "Optional module '$module_name' is not installed for $ASSEMBLY: $module_config"
        fi

        module_metadata="${SCRIPT_DIR}/modules/${module_name}/module.config"
        [[ -s "$module_metadata" ]] ||
            die "Optional module metadata is missing: $module_metadata"
        MODULE_SCOPE=""
        MODULE_REQUIRES_DESIGN=""
        MODULE_REQUIRES_CONTRASTS=""
        MODULE_OUTPUT_NAME=""
        # shellcheck disable=SC1090
        source "$module_metadata"
        module_scope="${MODULE_SCOPE:-}"
        module_requires_design="${MODULE_REQUIRES_DESIGN:-false}"
        module_requires_contrasts="${MODULE_REQUIRES_CONTRASTS:-false}"
        module_output_name="${MODULE_OUTPUT_NAME:-$module_name}"
        [[ "$module_scope" == "sample" ||
           "$module_scope" == "cohort" ||
           "$module_scope" == "hybrid" ]] ||
            die "Invalid MODULE_SCOPE for '$module_name': $module_scope"
        [[ "$module_requires_design" == "true" ||
           "$module_requires_design" == "false" ]] ||
            die "Invalid MODULE_REQUIRES_DESIGN for '$module_name'"
        [[ "$module_requires_contrasts" == "true" ||
           "$module_requires_contrasts" == "false" ]] ||
            die "Invalid MODULE_REQUIRES_CONTRASTS for '$module_name'"
        [[ "$module_output_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] ||
            die "Invalid MODULE_OUTPUT_NAME for '$module_name': $module_output_name"
        if [[ "$module_scope" == "sample" || "$module_scope" == "hybrid" ]]; then
            [[ -x "${SCRIPT_DIR}/modules/${module_name}/run_module.sh" ]] ||
                die "Module '$module_name' requires executable run_module.sh"
        fi
        if [[ "$module_scope" == "cohort" ]]; then
            [[ -x "${SCRIPT_DIR}/modules/${module_name}/run_cohort.sh" ]] ||
                die "Module '$module_name' requires executable run_cohort.sh"
        fi
        if [[ "$module_scope" == "hybrid" ]]; then
            [[ -f "${SCRIPT_DIR}/modules/${module_name}/aggregate_module.py" ]] ||
                die "Module '$module_name' requires aggregate_module.py"
        fi
        [[ "$module_requires_design" != "true" || -n "$DESIGN_FILE" ]] ||
            die "Optional module '$module_name' requires --design"
        [[ "$module_requires_contrasts" != "true" ||
           ${#CONTRASTS[@]} -gt 0 ]] ||
            die "Optional module '$module_name' requires at least one --contrast"

        seen_modules["$module_name"]=1
        SELECTED_MODULES+=("$module_name")
        MODULE_SCOPES["$module_name"]="$module_scope"
        MODULE_REQUIRES_DESIGN["$module_name"]="$module_requires_design"
        MODULE_REQUIRES_CONTRASTS["$module_name"]="$module_requires_contrasts"
        MODULE_OUTPUT_NAMES["$module_name"]="$module_output_name"
    done

    (( ${#SELECTED_MODULES[@]} > 0 )) ||
        die "None of the requested optional modules are installed for $ASSEMBLY"
    log_info "Selected optional modules: ${SELECTED_MODULES[*]}"
}

prepare_design() {
    local included_samples_file="${QC_DIR}/qc_included_samples.txt"
    local -a design_arguments
    local contrast

    [[ -n "$DESIGN_FILE" ]] || return 0
    [[ -s "$DESIGN_FILE" ]] || die "Design file not found or empty: $DESIGN_FILE"
    [[ -s "$included_samples_file" ]] ||
        die "QC-included sample list is required to validate the design"

    mkdir -p "$DESIGN_DIR"
    NORMALIZED_DESIGN="${DESIGN_DIR}/design.tsv"
    CONTRASTS_FILE="${DESIGN_DIR}/contrasts.tsv"
    design_arguments=(
        --design "$DESIGN_FILE"
        --samples-file "$included_samples_file"
        --output-design "$NORMALIZED_DESIGN"
        --output-contrasts "$CONTRASTS_FILE"
    )
    for contrast in "${CONTRASTS[@]}"; do
        design_arguments+=(--contrast "$contrast")
    done
    python3 "$DESIGN_VALIDATOR" "${design_arguments[@]}" ||
        die "Design or contrast validation failed"
    log_info "Validated experiment design: $NORMALIZED_DESIGN"
}

load_completed_core_samples() {
    local included_samples_file="${QC_DIR}/qc_included_samples.txt"
    local module_name
    local requires_sample_inputs=false
    local sample
    local trimmed_r1
    local trimmed_r2

    [[ -s "$included_samples_file" ]] ||
        die "Modules-only mode requires a completed core QC run: $included_samples_file"

    mapfile -t SAMPLES < "$included_samples_file"
    (( ${#SAMPLES[@]} > 0 )) ||
        die "The completed core run contains no QC-included samples"

    R1_PATHS=()
    R2_PATHS=()

    for module_name in "${SELECTED_MODULES[@]}"; do
        if [[ "${MODULE_SCOPES[$module_name]}" == "sample" ||
              "${MODULE_SCOPES[$module_name]}" == "hybrid" ]]; then
            requires_sample_inputs=true
            break
        fi
    done

    [[ "$requires_sample_inputs" == true ]] || return 0

    for sample in "${SAMPLES[@]}"; do
        [[ "$sample" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] ||
            die "Invalid sample identifier in $included_samples_file: $sample"

        if [[ "$READ_LAYOUT" == "paired" ]]; then
            trimmed_r1="${RESULTS_DIR}/${sample}/fastp/${sample}_trimmed_R1.fastq.gz"
            trimmed_r2="${RESULTS_DIR}/${sample}/fastp/${sample}_trimmed_R2.fastq.gz"
            [[ -s "$trimmed_r2" ]] ||
                die "Prior core R2 output is missing for $sample: $trimmed_r2"
        else
            trimmed_r1="${RESULTS_DIR}/${sample}/fastp/${sample}_trimmed.fastq.gz"
            trimmed_r2=""
        fi

        [[ -s "$trimmed_r1" ]] ||
            die "Prior core R1 output is missing for $sample: $trimmed_r1"

        R1_PATHS+=("$trimmed_r1")
        R2_PATHS+=("$trimmed_r2")
    done
}

load_current_core_samples() {
    local sample

    R1_PATHS=()
    R2_PATHS=()

    for sample in "${SAMPLES[@]}"; do
        if [[ "$READ_LAYOUT" == "paired" ]]; then
            R1_PATHS+=("${RESULTS_DIR}/${sample}/fastp/${sample}_trimmed_R1.fastq.gz")
            R2_PATHS+=("${RESULTS_DIR}/${sample}/fastp/${sample}_trimmed_R2.fastq.gz")
        else
            R1_PATHS+=("${RESULTS_DIR}/${sample}/fastp/${sample}_trimmed.fastq.gz")
            R2_PATHS+=("")
        fi
    done
}

run_selected_modules() {
    local module_name
    local module_runner
    local module_aggregator
    local cohort_runner
    local module_scope
    local module_output_name
    local index
    local sample
    local contrast
    local -a module_arguments
    local -a aggregate_arguments
    local -a cohort_arguments

    for module_name in "${SELECTED_MODULES[@]}"; do
        module_scope="${MODULE_SCOPES[$module_name]}"
        module_output_name="${MODULE_OUTPUT_NAMES[$module_name]}"

        if [[ "$module_scope" == "sample" || "$module_scope" == "hybrid" ]]; then
            module_runner="${SCRIPT_DIR}/modules/${module_name}/run_module.sh"
            for index in "${!SAMPLES[@]}"; do
                sample="${SAMPLES[$index]}"
                module_arguments=(
                    --sample "$sample"
                    --layout "$READ_LAYOUT"
                    --read1 "${R1_PATHS[$index]}"
                    --output-dir "${RESULTS_DIR}/${sample}/modules/${module_output_name}"
                    --assembly "$ASSEMBLY"
                    --db-root "$DB_ROOT"
                    --threads "$THREADS"
                )
                if [[ "$READ_LAYOUT" == "paired" ]]; then
                    module_arguments+=(--read2 "${R2_PATHS[$index]}")
                fi

                log_info "Running optional module '$module_name' for $sample"
                "$module_runner" "${module_arguments[@]}"
            done
        fi

        module_aggregator="${SCRIPT_DIR}/modules/${module_name}/aggregate_module.py"
        if [[ "$module_scope" == "hybrid" && -f "$module_aggregator" ]]; then
            aggregate_arguments=(
                --results-dir "$RESULTS_DIR"
                --output-dir "${MATRIX_DIR}/${module_output_name}"
            )
            for sample in "${SAMPLES[@]}"; do
                aggregate_arguments+=(--sample "$sample")
            done

            log_info "Aggregating optional module '$module_name' across the experiment"
            python3 "$module_aggregator" "${aggregate_arguments[@]}"
        fi

        if [[ "$module_scope" == "cohort" ]]; then
            cohort_runner="${SCRIPT_DIR}/modules/${module_name}/run_cohort.sh"
            cohort_arguments=(
                --results-dir "$RESULTS_DIR"
                --matrix-dir "$MATRIX_DIR"
                --output-dir "${MATRIX_DIR}/${module_output_name}"
                --samples-file "${QC_DIR}/qc_included_samples.txt"
                --assembly "$ASSEMBLY"
                --db-root "$DB_ROOT"
                --threads "$THREADS"
            )
            if [[ -n "$NORMALIZED_DESIGN" ]]; then
                cohort_arguments+=(
                    --design "$NORMALIZED_DESIGN"
                    --contrasts-file "$CONTRASTS_FILE"
                )
                for contrast in "${CONTRASTS[@]}"; do
                    cohort_arguments+=(--contrast "$contrast")
                done
            fi
            log_info "Running cohort module '$module_name'"
            "$cohort_runner" "${cohort_arguments[@]}"
        fi
    done
}

################################################################################
# 5. Validate runtime, references, and input
################################################################################

if [[ "$PIPELINE_MODE" == "modules" ]]; then
    [[ -d "$RESULTS_DIR" ]] ||
        die "Modules-only mode requires prior core results: $RESULTS_DIR"
else
    [[ -d "$READS_DIR" ]] ||
        die "FASTQ input directory not found: $READS_DIR"

    READS_DIR="$(cd -- "$READS_DIR" && pwd -P)"
fi

mkdir -p "$RESULTS_DIR"

RUN_ID="$(date -u '+%Y%m%dT%H%M%SZ')-$$"
RUN_START_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
RUN_START_EPOCH="$(date +%s)"
RUN_RECORDED=0
RUN_COMMAND=""
RUN_GIT_COMMIT="unknown"
RUN_GIT_DIRTY="unknown"

printf -v RUN_COMMAND '%q ' "$0" "${ORIGINAL_ARGUMENTS[@]}"
RUN_COMMAND="${RUN_COMMAND% }"

if command -v git >/dev/null 2>&1 &&
   git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    RUN_GIT_COMMIT="$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null || printf unknown)"
    if [[ -n "$(git -C "$SCRIPT_DIR" status --porcelain 2>/dev/null)" ]]; then
        RUN_GIT_DIRTY="yes"
    else
        RUN_GIT_DIRTY="no"
    fi
fi

tsv_safe() {
    local value="${1:-}"
    value="${value//$'\t'/ }"
    value="${value//$'\r'/ }"
    value="${value//$'\n'/ }"
    printf '%s' "$value"
}

record_project_run() {
    local exit_status="$1"
    local run_status="success"
    local run_end_utc
    local run_end_epoch
    local duration_seconds
    local modules_value="-"
    local input_value="-"
    local sample_count=0
    local sample_names="-"

    (( RUN_RECORDED == 0 )) || return 0
    RUN_RECORDED=1

    (( exit_status == 0 )) || run_status="failed"
    run_end_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    run_end_epoch="$(date +%s)"
    duration_seconds=$((run_end_epoch - RUN_START_EPOCH))

    if (( ${#SELECTED_MODULES[@]} > 0 )); then
        modules_value="$(IFS=,; printf '%s' "${SELECTED_MODULES[*]}")"
    elif [[ -n "$MODULES_REQUESTED" ]]; then
        modules_value="$MODULES_REQUESTED"
    fi

    [[ -z "$READS_DIR" ]] || input_value="$READS_DIR"

    if declare -p SAMPLES >/dev/null 2>&1; then
        sample_count="${#SAMPLES[@]}"
        if (( sample_count > 0 )); then
            sample_names="$(IFS=,; printf '%s' "${SAMPLES[*]}")"
        fi
    fi

    if [[ ! -s "$PROJECT_INFO_FILE" ]]; then
        printf '%s\n' \
            $'run_id\tstart_utc\tend_utc\tduration_seconds\tstatus\texit_code\texperiment\tdata_type\tlayout\tassembly\tpipeline\tmodules\tinput_path\tsample_count\tsamples\tthreads\thost\tuser\tgit_commit\tgit_dirty\tcommand\tresults_path' \
            > "$PROJECT_INFO_FILE"
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$(tsv_safe "$RUN_ID")" \
        "$(tsv_safe "$RUN_START_UTC")" \
        "$(tsv_safe "$run_end_utc")" \
        "$duration_seconds" \
        "$run_status" \
        "$exit_status" \
        "$(tsv_safe "$EXPERIMENT_NAME")" \
        "RNA-seq" \
        "$(tsv_safe "$READ_LAYOUT")" \
        "$(tsv_safe "$ASSEMBLY")" \
        "$(tsv_safe "$PIPELINE_MODE")" \
        "$(tsv_safe "$modules_value")" \
        "$(tsv_safe "$input_value")" \
        "$sample_count" \
        "$(tsv_safe "$sample_names")" \
        "$(tsv_safe "$THREADS")" \
        "$(tsv_safe "$(hostname 2>/dev/null || printf unknown)")" \
        "$(tsv_safe "${USER:-unknown}")" \
        "$(tsv_safe "$RUN_GIT_COMMIT")" \
        "$(tsv_safe "$RUN_GIT_DIRTY")" \
        "$(tsv_safe "$RUN_COMMAND")" \
        "$(tsv_safe "$RESULTS_DIR")" \
        >> "$PROJECT_INFO_FILE"
}

record_project_run_on_exit() {
    local exit_status=$?
    record_project_run "$exit_status"
}

trap record_project_run_on_exit EXIT

MAX_THREADS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo "unknown")"

[[ "$THREADS" =~ ^[1-9][0-9]*$ ]] ||
    die "THREADS must be a positive integer (configured: '$THREADS', available CPUs: $MAX_THREADS)"

if [[ "$MAX_THREADS" != "unknown" ]] && (( THREADS > MAX_THREADS )); then
    die "THREADS ($THREADS) exceeds the number of available CPUs ($MAX_THREADS)"
fi

if [[ "${CONDA_DEFAULT_ENV:-}" != "$CONDA_ENV" ]]; then
    die "Conda environment '$CONDA_ENV' is not active. Run: conda activate $CONDA_ENV"
fi

if [[ "$PIPELINE_MODE" != "modules" ]]; then
    log_info "Validating core software dependencies"

    REQUIRED_COMMANDS=(
        python3
        fastqc
        fastp
        STAR
        rsem-calculate-expression
        featureCounts
        samtools
        multiqc
        Rscript
    )

    for command_name in "${REQUIRED_COMMANDS[@]}"; do
        command -v "$command_name" >/dev/null 2>&1 ||
            die "Required command not found in PATH: $command_name"
    done
fi

log_info "Validating reference installation for $ASSEMBLY"

[[ -d "$STAR_INDEX" ]] ||
    die "STAR index directory not found: $STAR_INDEX"

STAR_INDEX_FILES=(
    "$STAR_INDEX/Genome"
    "$STAR_INDEX/SA"
    "$STAR_INDEX/SAindex"
    "$STAR_INDEX/chrName.txt"
    "$STAR_INDEX/genomeParameters.txt"
)

for index_file in "${STAR_INDEX_FILES[@]}"; do
    [[ -s "$index_file" ]] ||
        die "Required STAR index file is missing or empty: $index_file"
done

[[ -s "$GENOME_FASTA" ]] ||
    die "Genome FASTA not found or empty: $GENOME_FASTA"

[[ -s "$GTF" ]] ||
    die "GTF file not found or empty: $GTF"

[[ -s "$GENE_ANNOTATION" ]] ||
    die "Gene annotation table not found or empty: $GENE_ANNOTATION"

RSEM_REFERENCE_FILES=(
    "${RSEM_REFERENCE}.grp"
    "${RSEM_REFERENCE}.seq"
    "${RSEM_REFERENCE}.ti"
    "${RSEM_REFERENCE}.transcripts.fa"
)

for reference_file in "${RSEM_REFERENCE_FILES[@]}"; do
    [[ -s "$reference_file" ]] ||
        die "Required RSEM reference file is missing or empty: $reference_file"
done

if [[ "$PIPELINE_MODE" == "optional" || "$PIPELINE_MODE" == "modules" ]]; then
    resolve_selected_modules "$MODULES_REQUESTED"
fi

if [[ "$PIPELINE_MODE" == "modules" ]]; then
    load_completed_core_samples
    prepare_design
    run_selected_modules

    log_info "Optional modules completed successfully"
    log_info "Experiment:    $EXPERIMENT_NAME"
    log_info "Assembly:      $ASSEMBLY"
    log_info "Read layout:   $READ_LAYOUT"
    log_info "Modules:       ${SELECTED_MODULES[*]}"
    log_info "Samples:       ${#SAMPLES[@]}"
    log_info "Results root:  $RESULTS_DIR"
    log_info "Project info:  $PROJECT_INFO_FILE"
    exit 0
fi

mkdir -p \
    "$MATRIX_DIR" \
    "$MULTIQC_DIR" \
    "$LOG_DIR"

TIMING_FILE="${LOG_DIR}/sample_step_timings.tsv"
printf 'experiment\tsample\tstep\tstart_utc\tend_utc\tduration_seconds\tstatus\n' \
    > "$TIMING_FILE"

ACTIVE_SAMPLE=""
ACTIVE_STEP=""
STEP_START_EPOCH=0
STEP_START_UTC=""

begin_timed_step() {
    ACTIVE_SAMPLE="$1"
    ACTIVE_STEP="$2"
    STEP_START_EPOCH="$(date +%s)"
    STEP_START_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}

finish_timed_step() {
    local status="$1"
    local end_epoch
    local end_utc
    local duration_seconds

    [[ -n "$ACTIVE_STEP" ]] || return 0

    end_epoch="$(date +%s)"
    end_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    duration_seconds=$((end_epoch - STEP_START_EPOCH))

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$EXPERIMENT_NAME" \
        "$ACTIVE_SAMPLE" \
        "$ACTIVE_STEP" \
        "$STEP_START_UTC" \
        "$end_utc" \
        "$duration_seconds" \
        "$status" \
        >> "$TIMING_FILE"

    ACTIVE_SAMPLE=""
    ACTIVE_STEP=""
}

record_failed_timed_step() {
    local exit_status=$?

    if [[ -n "${ACTIVE_STEP:-}" ]]; then
        finish_timed_step "failed"
    fi

    exit "$exit_status"
}

trap record_failed_timed_step ERR

################################################################################
# 6. Discover FASTQ samples
################################################################################

log_info "Discovering $READ_LAYOUT-end FASTQ samples below $READS_DIR"

if [[ "$READ_LAYOUT" == "paired" ]]; then
    mapfile -d '' -t INPUT_FILES < <(
        find "$READS_DIR" -type f \
            \( -name '*_1.fastq.gz' \
               -o -name '*_1.fq.gz' \) \
            -print0 |
            sort -zV
    )
else
    mapfile -d '' -t INPUT_FILES < <(
        find "$READS_DIR" -type f \
            \( -name '*.fastq.gz' -o -name '*.fq.gz' \) \
            -print0 |
            sort -zV
    )
fi

(( ${#INPUT_FILES[@]} > 0 )) ||
    die "No supported $READ_LAYOUT-end FASTQ files found below $READS_DIR"

SAMPLES=()
R1_PATHS=()
R2_PATHS=()

declare -A SEEN_SAMPLES=()
declare -A R2_BY_PAIR_KEY=()

normalise_pair_key() {
    local pair_stem="$1"

    # Facility filenames may contain a mate-specific numeric field between a
    # stable prefix and biological label: PREFIX_1_LABEL_1 / PREFIX_8_LABEL_2.
    if [[ "$pair_stem" =~ ^(.+)_([0-9]+)_(.+)$ ]]; then
        PAIR_KEY="${BASH_REMATCH[1]}|${BASH_REMATCH[3]}"
    else
        PAIR_KEY="$pair_stem"
    fi
}

if [[ "$READ_LAYOUT" == "paired" ]]; then
    mapfile -d '' -t R2_FILES < <(
        find "$READS_DIR" -type f \
            \( -name '*_2.fastq.gz' \
               -o -name '*_2.fq.gz' \) \
            -print0 |
            sort -zV
    )

    for r2_candidate in "${R2_FILES[@]}"; do
        r2_filename="$(basename "$r2_candidate")"
        r2_directory="$(dirname "$r2_candidate")"
        r2_pair_stem="$r2_filename"
        r2_pair_stem="${r2_pair_stem%_2.fastq.gz}"
        r2_pair_stem="${r2_pair_stem%_2.fq.gz}"
        normalise_pair_key "$r2_pair_stem"
        directory_pair_key="${r2_directory}|${PAIR_KEY}"

        [[ -z "${R2_BY_PAIR_KEY[$directory_pair_key]+x}" ]] ||
            die "Ambiguous R2 pairing key '$PAIR_KEY' in $r2_directory"

        R2_BY_PAIR_KEY["$directory_pair_key"]="$r2_candidate"
    done
fi

for r1 in "${INPUT_FILES[@]}"; do
    filename="$(basename "$r1")"
    input_directory="$(dirname "$r1")"
    r2=""

    if [[ "$READ_LAYOUT" == "paired" ]]; then
        case "$filename" in
            *_1.fastq.gz|*_1.fq.gz)
                pair_stem="$filename"
                pair_stem="${pair_stem%.fastq.gz}"
                pair_stem="${pair_stem%.fq.gz}"
                sample="${pair_stem%_1}"

                if [[ "$filename" == *.fastq.gz ]]; then
                    r2="${input_directory}/${sample}_2.fastq.gz"
                else
                    r2="${input_directory}/${sample}_2.fq.gz"
                fi

                if [[ ! -e "$r2" ]]; then
                    normalise_pair_key "$sample"
                    directory_pair_key="${input_directory}|${PAIR_KEY}"
                    r2="${R2_BY_PAIR_KEY[$directory_pair_key]:-}"
                fi
                ;;
            *)
                continue
                ;;
        esac
    else
        sample="$filename"
        sample="${sample%.fastq.gz}"
        sample="${sample%.fq.gz}"
    fi

    [[ -n "$sample" ]] ||
        die "Could not derive a sample name from: $r1"

    [[ -z "${SEEN_SAMPLES[$sample]+x}" ]] ||
        die "Duplicate sample name detected from FASTQ filenames: $sample"

    [[ -s "$r1" ]] ||
        die "R1 FASTQ is missing or empty for sample $sample: $r1"

    if [[ "$READ_LAYOUT" == "paired" ]]; then
        [[ -s "$r2" ]] ||
            die "R2 FASTQ is missing or empty for sample $sample: $r2"
    fi

    SEEN_SAMPLES["$sample"]=1
    SAMPLES+=("$sample")
    R1_PATHS+=("$r1")
    R2_PATHS+=("$r2")
done

(( ${#SAMPLES[@]} > 0 )) ||
    die "No valid $READ_LAYOUT-end samples were discovered"

log_info "Discovered ${#SAMPLES[@]} $READ_LAYOUT-end sample(s)"

for index in "${!SAMPLES[@]}"; do
    if [[ "$READ_LAYOUT" == "paired" ]]; then
        log_info "  ${SAMPLES[$index]}: $(basename "${R1_PATHS[$index]}") + $(basename "${R2_PATHS[$index]}")"
    else
        log_info "  ${SAMPLES[$index]}: $(basename "${R1_PATHS[$index]}")"
    fi
done

################################################################################
# 7. Process each sample
################################################################################

for index in "${!SAMPLES[@]}"; do
    sample="${SAMPLES[$index]}"
    raw_r1="${R1_PATHS[$index]}"
    raw_r2="${R2_PATHS[$index]}"
    raw_reads=("$raw_r1")

    if [[ "$READ_LAYOUT" == "paired" ]]; then
        raw_reads+=("$raw_r2")
    fi

    log_info "Processing sample: $sample"

    sample_results_dir="${RESULTS_DIR}/${sample}"
    sample_fastqc_raw_dir="${sample_results_dir}/fastqc/raw"
    sample_fastqc_trimmed_dir="${sample_results_dir}/fastqc/trimmed"
    sample_fastp_dir="${sample_results_dir}/fastp"
    sample_star_dir="${sample_results_dir}/star"
    sample_rsem_dir="${sample_results_dir}/rsem"
    sample_featurecounts_dir="${sample_results_dir}/featurecounts"
    sample_log_dir="${sample_results_dir}/logs"

    mkdir -p \
        "$sample_fastqc_raw_dir" \
        "$sample_fastqc_trimmed_dir" \
        "$sample_fastp_dir" \
        "$sample_star_dir" \
        "$sample_rsem_dir" \
        "$sample_featurecounts_dir" \
        "$sample_log_dir"

    if [[ "$READ_LAYOUT" == "paired" ]]; then
        trimmed_r1="${sample_fastp_dir}/${sample}_trimmed_R1.fastq.gz"
        trimmed_r2="${sample_fastp_dir}/${sample}_trimmed_R2.fastq.gz"
    else
        trimmed_r1="${sample_fastp_dir}/${sample}_trimmed.fastq.gz"
        trimmed_r2=""
    fi

    fastp_html="${sample_fastp_dir}/${sample}.fastp.html"
    fastp_json="${sample_fastp_dir}/${sample}.fastp.json"

    star_prefix="${sample_star_dir}/${sample}."
    transcriptome_bam="${star_prefix}Aligned.toTranscriptome.out.bam"
    genomic_bam="${star_prefix}Aligned.sortedByCoord.out.bam"
    genomic_bam_index="${genomic_bam}.bai"

    rsem_prefix="${sample_rsem_dir}/${sample}"
    featurecounts_output="${sample_featurecounts_dir}/${sample}.featureCounts.tsv"

    ########################################################################
    # 7.1 Raw FASTQ quality control
    ########################################################################

    log_info "Running raw FastQC: $sample"

    begin_timed_step "$sample" "fastqc_raw"
    fastqc \
        --threads "$THREADS" \
        --outdir "$sample_fastqc_raw_dir" \
        "${raw_reads[@]}" \
        > "${sample_log_dir}/FastQC.raw.stdout.log" \
        2> "${sample_log_dir}/FastQC.raw.stderr.log"
    finish_timed_step "success"

    ########################################################################
    # 7.2 Adapter trimming and quality filtering
    ########################################################################

    log_info "Running fastp: $sample"

    fastp_arguments=(
        --thread "$THREADS"
        --in1 "$raw_r1"
        --out1 "$trimmed_r1"
        --html "$fastp_html"
        --json "$fastp_json"
    )

    if [[ "$READ_LAYOUT" == "paired" ]]; then
        fastp_arguments+=(
            --in2 "$raw_r2"
            --out2 "$trimmed_r2"
        )
    fi

    begin_timed_step "$sample" "fastp"
    fastp \
        "${fastp_arguments[@]}" \
        > "${sample_log_dir}/fastp.stdout.log" \
        2> "${sample_log_dir}/fastp.stderr.log"
    finish_timed_step "success"

    [[ -s "$trimmed_r1" ]] ||
        die "fastp did not produce a non-empty trimmed R1 file for sample: $sample"

    if [[ "$READ_LAYOUT" == "paired" ]]; then
        [[ -s "$trimmed_r2" ]] ||
            die "fastp did not produce a non-empty trimmed R2 file for sample: $sample"
    fi

    trimmed_reads=("$trimmed_r1")
    if [[ "$READ_LAYOUT" == "paired" ]]; then
        trimmed_reads+=("$trimmed_r2")
    fi

    ########################################################################
    # 7.3 Trimmed FASTQ quality control
    ########################################################################

    log_info "Running trimmed FastQC: $sample"

    begin_timed_step "$sample" "fastqc_trimmed"
    fastqc \
        --threads "$THREADS" \
        --outdir "$sample_fastqc_trimmed_dir" \
        "${trimmed_reads[@]}" \
        > "${sample_log_dir}/FastQC.trimmed.stdout.log" \
        2> "${sample_log_dir}/FastQC.trimmed.stderr.log"
    finish_timed_step "success"

    ########################################################################
    # 7.4 STAR alignment
    ########################################################################

    log_info "Running STAR: $sample"

    begin_timed_step "$sample" "star"
    STAR \
        --runThreadN "$THREADS" \
        --genomeDir "$STAR_INDEX" \
        --readFilesIn "${trimmed_reads[@]}" \
        --readFilesCommand zcat \
        --outFileNamePrefix "$star_prefix" \
        --outSAMtype BAM SortedByCoordinate \
        --quantMode TranscriptomeSAM GeneCounts \
        --twopassMode Basic \
        --outSAMattributes NH HI AS nM MD \
        > "${sample_log_dir}/STAR.stdout.log" \
        2> "${sample_log_dir}/STAR.stderr.log"
    finish_timed_step "success"

    [[ -s "$transcriptome_bam" ]] ||
        die "STAR transcriptome BAM was not produced or is empty for sample: $sample"

    [[ -s "$genomic_bam" ]] ||
        die "STAR genomic BAM was not produced or is empty for sample: $sample"

    log_info "Indexing genomic BAM: $sample"

    begin_timed_step "$sample" "samtools_index"
    samtools index \
        -@ "$THREADS" \
        "$genomic_bam" \
        > "${sample_log_dir}/samtools_index.stdout.log" \
        2> "${sample_log_dir}/samtools_index.stderr.log"
    finish_timed_step "success"

    [[ -s "$genomic_bam_index" ]] ||
        die "samtools did not produce a BAM index for sample: $sample"

    ########################################################################
    # 7.5 FeatureCounts integer gene quantification
    ########################################################################

    log_info "Running FeatureCounts: $sample"

    featurecounts_layout_arguments=()
    if [[ "$READ_LAYOUT" == "paired" ]]; then
        featurecounts_layout_arguments+=(--countReadPairs -p -B -C)
    fi

    begin_timed_step "$sample" "featurecounts"
    featureCounts \
        -T "$THREADS" \
        -F GTF \
        -t exon \
        -g gene_id \
        -s 0 \
        -Q 10 \
        "${featurecounts_layout_arguments[@]}" \
        -a "$GTF" \
        -o "$featurecounts_output" \
        "$genomic_bam" \
        > "${sample_log_dir}/FeatureCounts.stdout.log" \
        2> "${sample_log_dir}/FeatureCounts.stderr.log"
    finish_timed_step "success"

    [[ -s "$featurecounts_output" ]] ||
        die "FeatureCounts output was not produced or is empty for sample: $sample"
    [[ -s "${featurecounts_output}.summary" ]] ||
        die "FeatureCounts summary was not produced for sample: $sample"

    ########################################################################
    # 7.6 RSEM quantification
    ########################################################################

    log_info "Running RSEM: $sample"

    rsem_layout_arguments=()
    if [[ "$READ_LAYOUT" == "paired" ]]; then
        rsem_layout_arguments+=(--paired-end)
    fi

    begin_timed_step "$sample" "rsem"
    rsem-calculate-expression \
        "${rsem_layout_arguments[@]}" \
        --alignments \
        --bam \
        --no-bam-output \
        --estimate-rspd \
        --num-threads "$THREADS" \
        "$transcriptome_bam" \
        "$RSEM_REFERENCE" \
        "$rsem_prefix" \
        > "${sample_log_dir}/RSEM.stdout.log" \
        2> "${sample_log_dir}/RSEM.stderr.log"
    finish_timed_step "success"

    [[ -s "${rsem_prefix}.genes.results" ]] ||
        die "RSEM gene results were not produced or are empty for sample: $sample"

    [[ -s "${rsem_prefix}.isoforms.results" ]] ||
        die "RSEM isoform results were not produced or are empty for sample: $sample"

    log_info "Completed sample: $sample"
done

################################################################################
# 8. Validate sample QC and exclude failed samples
################################################################################

QC_MANIFEST="${LOG_DIR}/qc_input_manifest.tsv"
printf 'sample\tfastp_json\tstar_log\trsem_genes\n' > "$QC_MANIFEST"

for sample in "${SAMPLES[@]}"; do
    printf '%s\t%s\t%s\t%s\n' \
        "$sample" \
        "${RESULTS_DIR}/${sample}/fastp/${sample}.fastp.json" \
        "${RESULTS_DIR}/${sample}/star/${sample}.Log.final.out" \
        "${RESULTS_DIR}/${sample}/rsem/${sample}.genes.results" \
        >> "$QC_MANIFEST"
done

log_info "Running final RNA-seq QC validator"

if ! python3 "$QC_VALIDATOR" \
    --manifest "$QC_MANIFEST" \
    --config "$QC_CONFIG_FILE" \
    --output-dir "$QC_DIR" \
    > "${LOG_DIR}/QC_Validator.stdout.log" \
    2> "${LOG_DIR}/QC_Validator.stderr.log"; then
    die "QC validation failed; see ${LOG_DIR}/QC_Validator.stderr.log"
fi

mapfile -t QC_INCLUDED_SAMPLES < "${QC_DIR}/qc_included_samples.txt"

(( ${#QC_INCLUDED_SAMPLES[@]} > 0 )) ||
    die "All samples failed QC; no expression matrices will be generated"

SAMPLES=("${QC_INCLUDED_SAMPLES[@]}")
log_info "QC retained ${#SAMPLES[@]} sample(s) for experiment-level matrices"
prepare_design

################################################################################
# 9. Collect RSEM gene result files
################################################################################

GENE_RESULT_FILES=()

for sample in "${SAMPLES[@]}"; do
    result_file="${RESULTS_DIR}/${sample}/rsem/${sample}.genes.results"

    [[ -s "$result_file" ]] ||
        die "RSEM gene result file is missing or empty: $result_file"

    GENE_RESULT_FILES+=("$result_file")
done

################################################################################
# 10. Generate experiment-level count, TPM, and FPKM matrices
################################################################################

generate_rsem_matrix() {
    local column_number="$1"
    local output_file="$2"
    local temporary_dir
    local index
    local sample
    local result_file
    local value_file
    local -a value_files=()

    temporary_dir="$(mktemp -d "${MATRIX_DIR}/.matrix_tmp.XXXXXX")" ||
        die "Could not create a temporary matrix directory"

    if ! cut -f1 "${GENE_RESULT_FILES[0]}" | tail -n +2 > "${temporary_dir}/gene_ids"; then
        rm -rf "$temporary_dir"
        die "Could not extract gene identifiers from ${GENE_RESULT_FILES[0]}"
    fi

    for index in "${!SAMPLES[@]}"; do
        sample="${SAMPLES[$index]}"
        result_file="${GENE_RESULT_FILES[$index]}"
        value_file="${temporary_dir}/${index}.values"

        if ! cut -f"$column_number" "$result_file" | tail -n +2 > "$value_file"; then
            rm -rf "$temporary_dir"
            die "Could not extract column $column_number from $result_file"
        fi

        value_files+=("$value_file")
    done

    if ! {
        printf 'gene_id'

        for sample in "${SAMPLES[@]}"; do
            printf '\t%s' "$sample"
        done

        printf '\n'

        paste \
            "${temporary_dir}/gene_ids" \
            "${value_files[@]}"
    } > "$output_file"; then
        rm -rf "$temporary_dir"
        die "Could not generate matrix: $output_file"
    fi

    rm -rf "$temporary_dir"

    [[ -s "$output_file" ]] ||
        die "Generated matrix is missing or empty: $output_file"
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
            rm -rf "$temporary_dir"
            die "FeatureCounts gene order differs for sample: $sample"
        fi
        if ! awk '/^[0-9]+$/ {next} {exit 1}' "$value_file"; then
            rm -rf "$temporary_dir"
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
    rm -rf "$temporary_dir"
    [[ -s "$output_file" ]] || die "Could not generate matrix: $output_file"
}

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

log_info "Generating integer FeatureCounts gene-count matrix"
generate_featurecounts_matrix "$RAW_COUNTS_MATRIX"

log_info "Generating RSEM expected-count matrix"
generate_rsem_matrix 5 "$RSEM_COUNTS_MATRIX"

log_info "Generating gene-level TPM matrix"
generate_rsem_matrix 6 "$RAW_TPM_MATRIX"

log_info "Generating gene-level FPKM matrix"
generate_rsem_matrix 7 "$RAW_FPKM_MATRIX"

log_info "Annotating gene-level expression matrices"
python3 "$SCRIPT_DIR/lib/map_gene_ids.py" \
    --input "$RAW_COUNTS_MATRIX" \
    --mapping "$GENE_ANNOTATION" \
    --output "$COUNTS_MATRIX"
python3 "$SCRIPT_DIR/lib/map_gene_ids.py" \
    --input "$RAW_TPM_MATRIX" \
    --mapping "$GENE_ANNOTATION" \
    --output "$TPM_MATRIX"
python3 "$SCRIPT_DIR/lib/map_gene_ids.py" \
    --input "$RAW_FPKM_MATRIX" \
    --mapping "$GENE_ANNOTATION" \
    --output "$FPKM_MATRIX"

log_info "Resolving duplicate gene symbols using highest total expression"
Rscript "$SCRIPT_DIR/lib/handle_gene_dups.R" \
    --input "$COUNTS_MATRIX" \
    --output "$SYMBOL_COUNTS_MATRIX" \
    --strategy highest
Rscript "$SCRIPT_DIR/lib/handle_gene_dups.R" \
    --input "$TPM_MATRIX" \
    --output "$SYMBOL_TPM_MATRIX" \
    --strategy highest
Rscript "$SCRIPT_DIR/lib/handle_gene_dups.R" \
    --input "$FPKM_MATRIX" \
    --output "$SYMBOL_FPKM_MATRIX" \
    --strategy highest

MATRIX_MANIFEST="${MATRIX_DIR}/matrix_manifest.tsv"
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

################################################################################
# 11. MultiQC report
################################################################################

log_info "Running MultiQC"

multiqc \
    "$RESULTS_DIR" \
    --outdir "$MULTIQC_DIR" \
    --filename "multiqc_report.html" \
    --force \
    > "${LOG_DIR}/MultiQC.stdout.log" \
    2> "${LOG_DIR}/MultiQC.stderr.log"

MULTIQC_REPORT="${MULTIQC_DIR}/multiqc_report.html"

[[ -s "$MULTIQC_REPORT" ]] ||
    die "MultiQC report was not generated successfully: $MULTIQC_REPORT"

################################################################################
# 12. Optional modules
################################################################################

if [[ "$PIPELINE_MODE" == "optional" ]]; then
    load_current_core_samples
    run_selected_modules
fi

################################################################################
# 13. Completion
################################################################################

log_info "Pipeline completed successfully"
log_info "Pipeline mode: $PIPELINE_MODE"
log_info "Experiment:    $EXPERIMENT_NAME"
log_info "Species:       $SPECIES"
log_info "Assembly:      $ASSEMBLY"
log_info "Read layout:   $READ_LAYOUT"
log_info "Input root:    $READS_DIR"
log_info "Samples:       ${#SAMPLES[@]}"
log_info "Results root:  $RESULTS_DIR"
log_info "Step timings:  $TIMING_FILE"
log_info "QC status:     ${QC_DIR}/sample_qc_status.csv"
log_info "Counts matrix: $COUNTS_MATRIX"
log_info "TPM matrix:    $TPM_MATRIX"
log_info "FPKM matrix:   $FPKM_MATRIX"
log_info "Symbol counts: $SYMBOL_COUNTS_MATRIX"
log_info "Symbol TPM:    $SYMBOL_TPM_MATRIX"
log_info "Matrix index:  $MATRIX_MANIFEST"
log_info "MultiQC:       $MULTIQC_REPORT"
log_info "Project info:  $PROJECT_INFO_FILE"
if [[ "$PIPELINE_MODE" == "optional" ]]; then
    log_info "Modules:       ${SELECTED_MODULES[*]}"
fi
