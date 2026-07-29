# GSEA module

The `gsea` cohort module embeds the standalone `dqGSEA` package and implements
contrast-level preranked gene-set enrichment. It consumes the complete
statistics produced by the NF-RNAseq DGE module for every validated contrast.

The imported source is maintained as a Git subtree under `dqGSEA/` and
currently tracks upstream commit `d3d6d26` (dqGSEA 0.2.0).

## Installation

```bash
./install_pipe.sh --add-modules gsea --assembly GRCh38
```

The installer installs dqGSEA/fgsea and downloads a checksum-pinned human
MSigDB Hallmark v2024.1 symbol collection into
`db/shared/gsea_module/gene_sets/`. Collection provenance is recorded in every
run.

## Runtime

Run DGE and GSEA together:

```bash
./main.sh --assembly GRCh38 --layout single \
  --experiment EXPERIMENT --pipeline modules --modules dge,gsea \
  --design design.tsv --contrast condition:treated:control
```

GSEA can also run independently when the corresponding DGE contrast results
already exist:

```bash
./main.sh --assembly GRCh38 --layout single \
  --experiment EXPERIMENT --pipeline modules --modules gsea \
  --design design.tsv --contrast condition:treated:control
```

Results are written under `matrices/GSEA/contrasts/<contrast_id>/`:

- `gsea.csv`: complete pathway results
- `gsea_significant.csv`: pathways with adjusted p-value at most 0.05
- `gene_ranks.csv`: exact ranked input used by fgsea
- `gsea_plot.png`: top significant positive and negative pathways
- experiment-level `contrast_summary.tsv` and `run_metadata.tsv`

The sample-level ssGSEA/GSVA mode remains a separate future implementation.
