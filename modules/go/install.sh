#!/usr/bin/env bash

set -Eeuo pipefail

die() { printf '[go-install] ERROR: %s\n' "$*" >&2; exit 1; }
log_info() { printf '[go-install] %s\n' "$*"; }

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
        *) die "Unknown argument: $1" ;;
    esac
done

case "${ASSEMBLY,,}" in
    grch38|hg38) ASSEMBLY="GRCh38" ;;
    grch37|hg19) ASSEMBLY="GRCh37" ;;
    *) die "--assembly must be GRCh37, hg19, GRCh38, or hg38" ;;
esac
[[ -d "$DB_ROOT" ]] || die "--db-root was not found: $DB_ROOT"
[[ -n "$MODULE_DB_ROOT" && -n "$CONDA_ENV" ]] || die "Module DB root and Conda env are required"

if ! conda run --name "$CONDA_ENV" Rscript -e \
    'p <- c("clusterProfiler", "enrichplot", "org.Hs.eg.db", "ggplot2"); quit(status=ifelse(all(vapply(p, requireNamespace, logical(1), quietly=TRUE)), 0, 1))'
then
    log_info "Installing Gene Ontology R dependencies into '$CONDA_ENV'"
    conda install --name "$CONDA_ENV" --channel conda-forge --channel bioconda --yes \
        bioconductor-clusterprofiler bioconductor-enrichplot \
        bioconductor-org.hs.eg.db r-ggplot2
fi

conda run --name "$CONDA_ENV" Rscript -e \
    'stopifnot(requireNamespace("clusterProfiler", quietly=TRUE), requireNamespace("enrichplot", quietly=TRUE), requireNamespace("org.Hs.eg.db", quietly=TRUE)); cat(as.character(packageVersion("clusterProfiler")), "\n")' ||
    die "GO dependency verification failed"

CONFIG_DIR="${MODULE_DB_ROOT}/config"
mkdir -p "$CONFIG_DIR"
cat > "${CONFIG_DIR}/${ASSEMBLY}.config" <<EOF
GO_ASSEMBLY='$ASSEMBLY'
GO_CONDA_ENV='$CONDA_ENV'
GO_ORGDB='org.Hs.eg.db'
GO_ONTOLOGY='ALL'
EOF
log_info "Installed $ASSEMBLY configuration in $CONFIG_DIR"
