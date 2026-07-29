# DGE

A validated DESeq2/limma workflow for raw counts or normalized expression. It
is designed for standalone use and eventual invocation by an upstream RNA-seq
pipeline.

## Input contract

Counts are CSV or TSV with a `gene_id` column and one raw integer-count column
per sample. ENSEMBL IDs are expected in most workflows but other unique gene
identifiers are accepted. The design contains `sample_id` and `condition`.

```bash
DGE -d counts.csv -e design.csv -r Control -t Treatment
```

The default analysis uses DESeq2 and requires raw integer counts. Add
`--normalised` (`-n`) to analyse normalized continuous expression with
limma-trend. Non-negative normalized values such as TPM/FPKM are transformed
with `log2(x + 1)`; matrices containing negative values are treated as already
log-transformed.

If the design contains a column named exactly `batch`, it is automatically
included as a covariate in either model. Confounded designs fail explicitly.

For a two-condition design, `--test` is inferred. Use `DGE -h` for column-name,
filtering, annotation, and output options.

## Outputs

Results default to `results`:

- `dge.csv`: complete DESeq2 results.
- `dge_significant.csv`: results passing adjusted-P and fold-change thresholds.
- `volcano_plot.png`: teal negative and purple positive significant genes.
- `heatmap_top10_bottom10.png`: produced only with at least 10 significant
  genes; contains up to 10 genes from each fold-change extreme.
- `dds.rds`: fitted DESeq2 object, or `limma_fit.rds` for a limma method.

The workflow validates sample identity and order, uses an explicit
test-versus-reference contrast, and rejects normalized/non-integer input.
The default significance criteria are adjusted P below 0.05 and absolute log2
fold change of at least 1.
