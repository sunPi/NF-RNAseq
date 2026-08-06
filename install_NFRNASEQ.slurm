#!/bin/bash
# Install NF-RNAseq, GRCh38, GRCh37, and all implemented modules on ALICE3.
#SBATCH --job-name=install_NF_RNAseq
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=200G
#SBATCH --time=48:00:00
#SBATCH --partition=medium
#SBATCH --output=install_NF_RNAseq-%j.out
#SBATCH --error=install_NF_RNAseq-%j.err
#SBATCH --export=NONE

set -Eeuo pipefail

log() { printf '[NF-RNAseq install] %s\n' "$*"; }
die() { printf '[NF-RNAseq install] ERROR: %s\n' "$*" >&2; exit 1; }

module purge
module load gcc/12.3.0

PIPELINE_DIR="${SLURM_SUBMIT_DIR:?SLURM_SUBMIT_DIR is not set}"
INSTALLER="${PIPELINE_DIR}/install_pipe.sh"
[[ -x "$INSTALLER" ]] ||
    die "install_pipe.sh was not found in $PIPELINE_DIR; submit from the repository root"
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

if [[ -n "${SLURM_TMPDIR:-}" && -d "$SLURM_TMPDIR" ]]; then
    export TMPDIR="$SLURM_TMPDIR"
else
    export TMPDIR="${PIPELINE_DIR}/.install_tmp"
    mkdir -p "$TMPDIR"
fi
export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK}"
export OPENBLAS_NUM_THREADS="${SLURM_CPUS_PER_TASK}"
export MKL_NUM_THREADS="${SLURM_CPUS_PER_TASK}"

log "Job ID: ${SLURM_JOB_ID}; host: $(hostname); start: $(date --iso-8601=seconds)"
module list

"$INSTALLER" --with-hg19 --threads "${SLURM_CPUS_PER_TASK}" --skip-rrna

for assembly in GRCh38 GRCh37; do
    "$INSTALLER" --assembly "$assembly" \
        --threads "${SLURM_CPUS_PER_TASK}" --add-modules all
done

conda activate nf-env
for assembly in GRCh38 GRCh37; do
    "$INSTALLER" --assembly "$assembly" --skip-rrna --validate-only
    "$INSTALLER" --assembly "$assembly" --add-modules all --validate-only
done

log "Installation and validation completed at $(date --iso-8601=seconds)"
