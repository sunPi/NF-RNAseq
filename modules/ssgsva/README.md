# ssGSVA module

The `ssgsva` cohort module embeds the standalone ssGSVA 2.0.0 package and
calculates both ssGSEA and GSVA pathway scores for every sample.

It uses the pipeline's highest-expression symbol-deduplicated TPM matrix:

`matrices/annotated/deduplicated/gene_TPM.highest.tsv`

This avoids summing duplicate symbols while matching symbol-based gene sets.

## Installation

```bash
./install_pipe.sh --add-modules ssgsva --assembly GRCh38
```

The installer installs GSVA and a checksum-pinned human MSigDB Hallmark
v2024.1 collection.

## Without a design

```bash
./main.sh --assembly GRCh38 --layout single \
  --experiment EXPERIMENT --pipeline modules --modules ssgsva
```

This produces per-sample ssGSEA and GSVA score matrices.

## With a design

```bash
./main.sh --assembly GRCh38 --layout single \
  --experiment EXPERIMENT --pipeline modules --modules ssgsva \
  --design design.tsv --contrast condition:treated:control
```

Scores are always calculated. When contrasts are supplied, the adapter also
uses limma to test pathway-score differences for each method and contrast.
Optional `batch` or `covariate_batch` columns are included in that model.

Results are written under `matrices/ssGSVA/`:

- `ssgsea/scores.tsv` and native CSV/RDS/plot outputs
- `gsva/scores.tsv` and native CSV/RDS/plot outputs
- `differential/<method>/<contrast_id>/complete_results.tsv`
- `differential/<method>/<contrast_id>/significant_padj_0.05.tsv`
- `differential_summary.tsv` when contrasts are present
- `run_metadata.tsv`
