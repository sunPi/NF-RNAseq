#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ASSEMBLY=""; MODULE_DB_ROOT=""; CONDA_ENV=""
while (( $# )); do case "$1" in
  --assembly) ASSEMBLY="$2"; shift 2;; --module-db-root) MODULE_DB_ROOT="$2"; shift 2;;
  --conda-env) CONDA_ENV="$2"; shift 2;; --db-root|--threads) shift 2;;
  *) printf '[decoupler-install] ERROR: Unknown argument: %s\n' "$1" >&2; exit 1;; esac; done
case "${ASSEMBLY,,}" in grch38|hg38) ASSEMBLY=GRCh38;; grch37|hg19) ASSEMBLY=GRCh37;; *) exit 1;; esac
conda install --name "$CONDA_ENV" --channel conda-forge --channel bioconda --yes \
  bioconductor-decoupler bioconductor-limma bioconductor-omnipathr \
  r-ggplot2 r-ggprism r-matrix
mkdir -p "$MODULE_DB_ROOT/networks" "$MODULE_DB_ROOT/config"
COLLECTRI_TSV="$MODULE_DB_ROOT/networks/collectri_human.tsv"
PROGENY_TSV="$MODULE_DB_ROOT/networks/progeny_human.tsv"
if [[ ! -s "$COLLECTRI_TSV" ]]; then
  curl --fail --location --retry 3 --continue-at - \
    'https://omnipathdb.org/interactions?datasets=collectri&organisms=9606&format=tsv&genesymbols=1' \
    --output "${COLLECTRI_TSV}.partial"
  mv -- "${COLLECTRI_TSV}.partial" "$COLLECTRI_TSV"
fi
if [[ ! -s "$PROGENY_TSV" ]]; then
  curl --fail --location --retry 3 --continue-at - \
    'https://omnipathdb.org/annotations?resources=PROGENy&format=tsv' \
    --output "${PROGENY_TSV}.partial"
  mv -- "${PROGENY_TSV}.partial" "$PROGENY_TSV"
fi
conda run --name "$CONDA_ENV" Rscript -e '
  args <- commandArgs(TRUE)
  c <- read.delim(args[1], check.names=FALSE)
  c <- data.frame(source=c$source_genesymbol, target=c$target_genesymbol,
                  mor=ifelse(c$consensus_stimulation=="True",1,
                      ifelse(c$consensus_inhibition=="True",-1,0)))
  c <- c[nzchar(c$source)&nzchar(c$target),]
  c <- aggregate(mor ~ source + target, c, mean)
  saveRDS(c,args[2])
  p <- read.delim(args[3], check.names=FALSE)
  p <- tidyr::pivot_wider(p[p$label %in% c("weight","p_value","pathway"),],
                          id_cols=c("genesymbol","record_id"),
                          names_from="label",values_from="value")
  p$weight <- as.numeric(p$weight); p$p_value <- as.numeric(p$p_value)
  p <- p[order(p$pathway,p$p_value),]
  p <- do.call(rbind,lapply(split(p,p$pathway),head,500))
  p <- data.frame(source=p$pathway,target=p$genesymbol,weight=p$weight,p_value=p$p_value)
  p <- p[order(p$source,p$target,p$p_value),]
  p <- p[!duplicated(p[c("source","target")]),]
  saveRDS(p,args[4])
' "$COLLECTRI_TSV" \
  "$MODULE_DB_ROOT/networks/collectri_human.rds" \
  "$PROGENY_TSV" \
  "$MODULE_DB_ROOT/networks/progeny_human_top500.rds"
cat > "$MODULE_DB_ROOT/config/${ASSEMBLY}.config" <<EOF
DECOUPLER_CONDA_ENV='$CONDA_ENV'
DECOUPLER_COLLECTRI='$MODULE_DB_ROOT/networks/collectri_human.rds'
DECOUPLER_PROGENY='$MODULE_DB_ROOT/networks/progeny_human_top500.rds'
EOF
printf '[decoupler-install] Installed for %s\n' "$ASSEMBLY"
