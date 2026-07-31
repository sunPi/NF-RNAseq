#!/usr/bin/env bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ASSEMBLY=""; DB_ROOT=""; MODULE_DB_ROOT=""; CONDA_ENV=""; THREADS=8
SIGNATURE_SHA256="d8e6bd55b261d7e87cce2c06f11e949685a8f6a0095392ef2e19722043022450"
die() { printf '[sarsig-install] ERROR: %s\n' "$*" >&2; exit 1; }
while (( $# )); do case "$1" in
    --assembly) ASSEMBLY="$2"; shift 2;; --db-root) DB_ROOT="$2"; shift 2;;
    --module-db-root) MODULE_DB_ROOT="$2"; shift 2;; --conda-env) CONDA_ENV="$2"; shift 2;;
    --threads) THREADS="$2"; shift 2;; *) die "Unknown argument: $1";; esac; done
case "${ASSEMBLY,,}" in grch38|hg38) ASSEMBLY=GRCh38;; grch37|hg19) ASSEMBLY=GRCh37;; *) die "Unsupported assembly";; esac
[[ -d "$DB_ROOT" && -n "$MODULE_DB_ROOT" && -n "$CONDA_ENV" ]] || die "Installation paths are incomplete"
command -v sha256sum >/dev/null 2>&1 || die "sha256sum is required"

if ! conda run --name "$CONDA_ENV" Rscript -e \
  'p<-c("ggplot2","ggprism");quit(status=ifelse(all(vapply(p,requireNamespace,logical(1),quietly=TRUE)),0,1))'; then
    conda install --name "$CONDA_ENV" --channel conda-forge --yes r-ggplot2 r-ggprism
fi
[[ "$(sha256sum "${SCRIPT_DIR}/signature/SarSig.txt" | awk '{print $1}')" == "$SIGNATURE_SHA256" ]] ||
    die "Bundled SarSig signature checksum does not match"
mkdir -p "$MODULE_DB_ROOT/signatures" "$MODULE_DB_ROOT/config"
cp "${SCRIPT_DIR}/signature/SarSig.txt" "$MODULE_DB_ROOT/signatures/SarSig.txt"
cat > "$MODULE_DB_ROOT/config/${ASSEMBLY}.config" <<EOF
SARSIG_CONDA_ENV='$CONDA_ENV'
SARSIG_SIGNATURE='$MODULE_DB_ROOT/signatures/SarSig.txt'
SARSIG_SIGNATURE_SHA256='$SIGNATURE_SHA256'
SARSIG_SIGNATURE_GENES='63'
EOF
printf '[sarsig-install] Installed for %s\n' "$ASSEMBLY"
