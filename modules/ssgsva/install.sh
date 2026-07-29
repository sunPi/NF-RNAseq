#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
COLLECTION_VERSION="MSigDB-v2024.1-Hs"
GMT_FILENAME="h.all.v2024.1.Hs.symbols.gmt"
GMT_SHA256="ee2463540042078bfa3f67828e1e223bb354446d9fbb4d22845866835ba5c772"
GMT_URL="https://raw.githubusercontent.com/sunPi/quick_gsea/bef36af6d1922dcd4686465af2dfa514e6febcf2/msigdb/${GMT_FILENAME}"

log_info() {
    printf '[ssgsva-install] %s\n' "$*"
}

die() {
    printf '[ssgsva-install] ERROR: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage:
  install.sh --assembly GRCh37|GRCh38 --db-root DIR \
    --module-db-root DIR --conda-env NAME [--threads N]

Installs the embedded ssGSVA package and a pinned human MSigDB Hallmark
v2024.1 symbol collection.
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
command -v curl >/dev/null 2>&1 || die "curl is required"
command -v sha256sum >/dev/null 2>&1 || die "sha256sum is required"

if ! conda run --name "$CONDA_ENV" Rscript -e \
    'packages <- c("GSVA", "GSEABase", "limma", "ggplot2", "ggprism");
     quit(status=ifelse(all(vapply(packages, requireNamespace, logical(1), quietly=TRUE)), 0, 1))'
then
    log_info "Installing ssGSVA dependencies into Conda environment '$CONDA_ENV'"
    conda install --name "$CONDA_ENV" \
        --channel conda-forge --channel bioconda \
        --yes \
        bioconductor-gsva \
        bioconductor-gseabase \
        bioconductor-limma \
        r-ggplot2 \
        r-ggprism
fi

log_info "Installing embedded ssGSVA package"
conda run --name "$CONDA_ENV" R CMD INSTALL --no-multiarch \
    "${SCRIPT_DIR}/ssGSVA" ||
    die "Embedded ssGSVA package installation failed"

GENE_SET_DIR="${MODULE_DB_ROOT}/gene_sets"
GMT_PATH="${GENE_SET_DIR}/${GMT_FILENAME}"
mkdir -p "$GENE_SET_DIR"
if [[ ! -s "$GMT_PATH" ]] ||
   [[ "$(sha256sum "$GMT_PATH" | awk '{print $1}')" != "$GMT_SHA256" ]]
then
    log_info "Downloading pinned $COLLECTION_VERSION Hallmark collection"
    curl --fail --location --retry 3 --output "${GMT_PATH}.partial" "$GMT_URL"
    printf '%s  %s\n' "$GMT_SHA256" "${GMT_PATH}.partial" |
        sha256sum --check --status ||
        die "Hallmark GMT checksum verification failed"
    mv "${GMT_PATH}.partial" "$GMT_PATH"
fi

conda run --name "$CONDA_ENV" Rscript -e \
    'stopifnot(requireNamespace("ssGSVA", quietly=TRUE));
     cat("ssGSVA ", as.character(packageVersion("ssGSVA")),
         "; GSVA ", as.character(packageVersion("GSVA")), "\n", sep="")' ||
    die "ssGSVA installation verification failed"

CONFIG_DIR="${MODULE_DB_ROOT}/config"
mkdir -p "$CONFIG_DIR"
cat > "${CONFIG_DIR}/${ASSEMBLY}.config" <<EOF
SSGSVA_ASSEMBLY='$ASSEMBLY'
SSGSVA_CONDA_ENV='$CONDA_ENV'
SSGSVA_ENGINE='ssGSVA'
SSGSVA_ENGINE_VERSION='2.0.0'
SSGSVA_GMT='$GMT_PATH'
SSGSVA_COLLECTION='$COLLECTION_VERSION'
SSGSVA_GMT_SHA256='$GMT_SHA256'
SSGSVA_METHOD='both'
EOF

log_info "Installed $ASSEMBLY configuration in $CONFIG_DIR"
