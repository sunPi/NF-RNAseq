#!/bin/bash
#
# Submit NF-RNAseq as one generously sized ALICE3 batch job.
# Pass normal main.sh arguments after this filename, for example:
#   sbatch run_NFRNASEQ.slurm --assembly GRCh38 --layout paired \
#     --experiment study_01 --input /shared/data/study_01 --pipeline core
#
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

log() {
    printf '[NF-RNAseq job] %s\n' "$*"
}

die() {
    printf '[NF-RNAseq job] ERROR: %s\n' "$*" >&2
    exit 1
}

(( $# > 0 )) || die "No main.sh arguments supplied"

module purge
module load gcc/12.3.0

# sbatch sets this to the directory from which the job was submitted. Submit
# this script from the NF-RNAseq repository so local configuration and results
# resolve exactly as they do in an interactive run.
PIPELINE_DIR="${SLURM_SUBMIT_DIR:?SLURM_SUBMIT_DIR is not set}"
MAIN_SCRIPT="${PIPELINE_DIR}/main.sh"
[[ -x "$MAIN_SCRIPT" ]] ||
    die "main.sh was not found in $PIPELINE_DIR; submit from the NF-RNAseq repository"
cd "$PIPELINE_DIR"

CONDA_SH=""
for candidate in \
    "$HOME/miniforge3/etc/profile.d/conda.sh" \
    "$HOME/mambaforge/etc/profile.d/conda.sh" \
    "$HOME/miniconda3/etc/profile.d/conda.sh" \
    "$HOME/anaconda3/etc/profile.d/conda.sh"
do
    if [[ -f "$candidate" ]]; then
        CONDA_SH="$candidate"
        break
    fi
done
[[ -n "$CONDA_SH" ]] || die "Could not find a Conda installation below $HOME"

# shellcheck disable=SC1090
source "$CONDA_SH"
conda activate nf-env

export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK}"
export OPENBLAS_NUM_THREADS="${SLURM_CPUS_PER_TASK}"
export MKL_NUM_THREADS="${SLURM_CPUS_PER_TASK}"

log "Job ID:       ${SLURM_JOB_ID}"
log "Host:         $(hostname)"
log "Start time:   $(date --iso-8601=seconds)"
log "Pipeline:     $PIPELINE_DIR"
log "CPUs:         ${SLURM_CPUS_PER_TASK}"
log "Memory:       200G"
log "Arguments:    $*"
module list

"$MAIN_SCRIPT" "$@"

log "Pipeline completed successfully"
log "End time: $(date --iso-8601=seconds)"
