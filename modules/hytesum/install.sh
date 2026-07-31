#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PIPELINE_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd -P)"
ASSEMBLY=""; DB_ROOT=""; MODULE_DB_ROOT=""; CONDA_ENV=""; THREADS=8
VERSION="MSigDB-v2024.1-Hs"
GMT_NAME="h.all.v2024.1.Hs.symbols.gmt"
GMT_SHA="ee2463540042078bfa3f67828e1e223bb354446d9fbb4d22845866835ba5c772"
GMT_URL="https://raw.githubusercontent.com/sunPi/quick_gsea/bef36af6d1922dcd4686465af2dfa514e6febcf2/msigdb/${GMT_NAME}"
die() { printf '[hytesum-install] ERROR: %s\n' "$*" >&2; exit 1; }
while (( $# )); do case "$1" in
    --assembly) ASSEMBLY="$2"; shift 2;; --db-root) DB_ROOT="$2"; shift 2;;
    --module-db-root) MODULE_DB_ROOT="$2"; shift 2;; --conda-env) CONDA_ENV="$2"; shift 2;;
    --threads) THREADS="$2"; shift 2;; *) die "Unknown argument: $1";; esac; done
case "${ASSEMBLY,,}" in grch38|hg38) ASSEMBLY=GRCh38;; grch37|hg19) ASSEMBLY=GRCh37;; *) die "Unsupported assembly";; esac
[[ -d "$DB_ROOT" && -n "$MODULE_DB_ROOT" && -n "$CONDA_ENV" ]] || die "Installation paths are incomplete"

if ! conda run --name "$CONDA_ENV" Rscript -e \
  'p<-c("GSVA","GSEABase","ggplot2","ggprism","writexl");quit(status=ifelse(all(vapply(p,requireNamespace,logical(1),quietly=TRUE)),0,1))'; then
    conda install --name "$CONDA_ENV" --channel conda-forge --channel bioconda --yes \
      bioconductor-gsva bioconductor-gseabase r-ggplot2 r-ggprism r-writexl
fi
conda run --name "$CONDA_ENV" R CMD INSTALL --no-multiarch \
    "${PIPELINE_ROOT}/modules/ssgsva/ssGSVA" || die "Embedded ssGSVA installation failed"

mkdir -p "$MODULE_DB_ROOT/gene_sets" "$MODULE_DB_ROOT/config"
FULL_GMT="$MODULE_DB_ROOT/gene_sets/$GMT_NAME"
if [[ ! -s "$FULL_GMT" ]] || [[ "$(sha256sum "$FULL_GMT" | awk '{print $1}')" != "$GMT_SHA" ]]; then
    curl --fail --location --retry 3 --output "${FULL_GMT}.partial" "$GMT_URL"
    printf '%s  %s\n' "$GMT_SHA" "${FULL_GMT}.partial" | sha256sum --check --status || die "GMT checksum failed"
    mv "${FULL_GMT}.partial" "$FULL_GMT"
fi
cat > "$MODULE_DB_ROOT/config/${ASSEMBLY}.config" <<EOF
HYTESUM_CONDA_ENV='$CONDA_ENV'
HYTESUM_GMT='$FULL_GMT'
HYTESUM_GMT_SHA256='$GMT_SHA'
HYTESUM_COLLECTION='$VERSION Hallmark'
EOF
printf '[hytesum-install] Installed for %s\n' "$ASSEMBLY"
