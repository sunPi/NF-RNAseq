#!/bin/bash
# Submit NF-RNAseq as one generously sized ALICE3 batch job.
# Pass normal main.sh arguments after this filename.
#SBATCH --job-name=NF_RNAseq
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=200G
#SBATCH --time=48:00:00
#SBATCH --partition=medium
#SBATCH --output=NF_RNAseq-%j.out
#SBATCH --error=NF_RNAseq-%j.err
#SBATCH --export=NONE

set -Eeuo pipefail

log() { printf '[NF-RNAseq job] %s\n' "$*"; }
die() { printf '[NF-RNAseq job] ERROR: %s\n' "$*" >&2; exit 1; }

(( $# > 0 )) || die "No main.sh arguments supplied"

# Keep scheduler-run projects and experiments separate under results/HPC/.
RUN_ARGUMENTS=()
EXPERIMENT_FOUND=false
PROJECT_FOUND=false
while (( $# > 0 )); do
    case "$1" in
        --project)
            (( $# >= 2 )) || die "Missing value after $1"
            [[ -n "$2" ]] || die "Project name cannot be empty"
            RUN_ARGUMENTS+=("--experiment" "HPC/$2")
            PROJECT_FOUND=true
            shift 2
            ;;
        --project=*)
            project="${1#*=}"
            [[ -n "$project" ]] || die "Project name cannot be empty"
            RUN_ARGUMENTS+=("--experiment=HPC/${project}")
            PROJECT_FOUND=true
            shift
            ;;
        -e|--experiment)
            (( $# >= 2 )) || die "Missing value after $1"
            experiment="$2"
            [[ -n "$experiment" ]] || die "Experiment name cannot be empty"
            [[ "$experiment" == HPC/* ]] || experiment="HPC/${experiment}"
            RUN_ARGUMENTS+=("$1" "$experiment")
            EXPERIMENT_FOUND=true
            shift 2
            ;;
        --experiment=*)
            experiment="${1#*=}"
            [[ -n "$experiment" ]] || die "Experiment name cannot be empty"
            [[ "$experiment" == HPC/* ]] || experiment="HPC/${experiment}"
            RUN_ARGUMENTS+=("--experiment=${experiment}")
            EXPERIMENT_FOUND=true
            shift
            ;;
        *)
            RUN_ARGUMENTS+=("$1")
            shift
            ;;
    esac
done
[[ "$PROJECT_FOUND" != true || "$EXPERIMENT_FOUND" != true ]] ||
    die "Use either --project or --experiment, not both"
[[ "$EXPERIMENT_FOUND" == true || "$PROJECT_FOUND" == true ]] ||
    die "A --project or --experiment value is required"

module purge
module load gcc/12.3.0

PIPELINE_DIR="${SLURM_SUBMIT_DIR:?SLURM_SUBMIT_DIR is not set}"
MAIN_SCRIPT="${PIPELINE_DIR}/main.sh"
[[ -x "$MAIN_SCRIPT" ]] ||
    die "main.sh was not found in $PIPELINE_DIR; submit from the repository root"
cd "$PIPELINE_DIR"

CONDA_SH=""
for candidate in \
    "$HOME/miniforge3/etc/profile.d/conda.sh" \
    "$HOME/mambaforge/etc/profile.d/conda.sh" \
    "$HOME/miniconda3/etc/profile.d/conda.sh" \
    "$HOME/anaconda3/etc/profile.d/conda.sh"
do
    if [[ -f "$candidate" ]]; then CONDA_SH="$candidate"; break; fi
done
[[ -n "$CONDA_SH" ]] || die "Could not find a Conda installation below $HOME"
# shellcheck disable=SC1090
source "$CONDA_SH"
conda activate nf-env

export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK}"
export OPENBLAS_NUM_THREADS="${SLURM_CPUS_PER_TASK}"
export MKL_NUM_THREADS="${SLURM_CPUS_PER_TASK}"

printf -v DISPLAY_ARGUMENTS '%q ' "${RUN_ARGUMENTS[@]}"
log "Job ID: ${SLURM_JOB_ID}; host: $(hostname); start: $(date --iso-8601=seconds)"
log "CPUs: ${SLURM_CPUS_PER_TASK}; memory: 200G"
log "Arguments: ${DISPLAY_ARGUMENTS% }"
module list

"$MAIN_SCRIPT" "${RUN_ARGUMENTS[@]}"

log "Pipeline completed successfully at $(date --iso-8601=seconds)"
