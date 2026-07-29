# DGE module

The `dge` cohort module runs DESeq2 on the pipeline's canonical annotated
integer gene-count matrix:

`matrices/annotated/gene_counts.tsv`

It deliberately does not use fractional RSEM expected counts or a
gene-symbol-deduplicated matrix. Ensembl gene IDs remain the statistical row
identity; gene symbols and biotypes are carried into result tables.

## Design

The module requires a validated design and at least one directed contrast:

```text
--design design.tsv --contrast condition:treated:control
```

Every contrast factor is included in the model. Optional adjustment variables
must be design columns prefixed with `covariate_`, for example
`covariate_batch`. Columns such as `replicate` remain metadata and are not
silently treated as covariates.

## Outputs

Results are written under `matrices/dge`:

- `normalized_counts.tsv`
- `variance_stabilized_expression.tsv`
- `contrast_summary.tsv`
- `run_metadata.tsv`
- `QC/PCA.pdf`
- `QC/sample_distances.tsv`
- `QC/sample_distance_heatmap.pdf`
- `contrasts/<contrast_id>/complete_results.tsv`
- `contrasts/<contrast_id>/significant_padj_0.05.tsv`
- per-contrast MA and volcano plots

Install with:

```bash
./install_pipe.sh --add-modules dge --assembly GRCh38
```
