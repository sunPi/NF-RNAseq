#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

log_info() {
    printf '[dge-install] %s\n' "$*"
}

die() {
    printf '[dge-install] ERROR: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage:
  install.sh --assembly GRCh37|GRCh38 --db-root DIR \
    --module-db-root DIR --conda-env NAME [--threads N]

Installs the embedded DGE package and its dependencies in the pipeline
Conda environment. No assembly-specific reference files are required.
EOF
}

ASSEMBLY=""
DB_ROOT=""
MODULE_DB_ROOT=""
CONDA_ENV=""
THREADS=8

while (( $# > 0 )); do
    case "$1" in
        --assembly) ASSEMBLY="$2"; shift 2 ;;
        --db-root) DB_ROOT="$2"; shift 2 ;;
        --module-db-root) MODULE_DB_ROOT="$2"; shift 2 ;;
        --conda-env) CONDA_ENV="$2"; shift 2 ;;
        --threads) THREADS="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) die "Unknown argument: $1" ;;
    esac
done

case "${ASSEMBLY,,}" in
    grch38|hg38) ASSEMBLY="GRCh38" ;;
    grch37|hg19) ASSEMBLY="GRCh37" ;;
    *) die "--assembly must be GRCh37, hg19, GRCh38, or hg38" ;;
esac

[[ -d "$DB_ROOT" ]] || die "--db-root was not found: $DB_ROOT"
[[ -n "$MODULE_DB_ROOT" ]] || die "--module-db-root is required"
[[ -n "$CONDA_ENV" ]] || die "--conda-env is required"
[[ "$THREADS" =~ ^[1-9][0-9]*$ ]] || die "--threads must be a positive integer"
command -v conda >/dev/null 2>&1 || die "conda is required"

if ! conda run --name "$CONDA_ENV" Rscript -e \
    'packages <- c("DESeq2", "EnhancedVolcano", "limma", "ggplot2", "ggprism", "SummarizedExperiment");
     quit(status=ifelse(all(vapply(packages, requireNamespace, logical(1), quietly=TRUE)), 0, 1))'
then
    log_info "Installing DGE dependencies into Conda environment '$CONDA_ENV'"
    conda install --name "$CONDA_ENV" \
        --channel conda-forge --channel bioconda \
        --yes \
        bioconductor-deseq2 \
        bioconductor-enhancedvolcano \
        bioconductor-limma \
        r-ggplot2 \
        r-ggprism
fi

log_info "Installing embedded DGE package"
conda run --name "$CONDA_ENV" R CMD INSTALL --no-multiarch \
    "${SCRIPT_DIR}/DGE" ||
    die "Embedded DGE package installation failed"

conda run --name "$CONDA_ENV" Rscript -e \
    'stopifnot(requireNamespace("DGE", quietly=TRUE));
     cat("DGE ", as.character(packageVersion("DGE")),
         "; DESeq2 ", as.character(packageVersion("DESeq2")), "\n", sep="")' ||
    die "DGE installation verification failed"

CONFIG_DIR="${MODULE_DB_ROOT}/config"
mkdir -p "$CONFIG_DIR"
cat > "${CONFIG_DIR}/${ASSEMBLY}.config" <<EOF
DGE_ASSEMBLY='$ASSEMBLY'
DGE_CONDA_ENV='$CONDA_ENV'
DGE_INPUT='matrices/annotated/gene_counts.tsv'
DGE_METHOD='DESeq2'
DGE_ENGINE='DGE'
DGE_ENGINE_VERSION='0.4.0'
EOF

log_info "Installed $ASSEMBLY configuration in $CONFIG_DIR"
