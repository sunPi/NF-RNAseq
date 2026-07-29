# dqGSEA

`dqGSEA` runs preranked gene set enrichment analysis from a differential
expression results table. It is designed to follow `DGE`, but accepts any table
containing gene identifiers and a numeric ranking statistic.

## Usage

```bash
dqGSEA -d results/dge.csv -g pathways.gmt
```

By default, dqGSEA uses the `stat` column for ranking and prefers
`gene_symbol` over `gene_id` for pathway matching. Columns can be selected
explicitly:

```bash
dqGSEA -d results/dge.csv -g pathways.gmt \
  --gene-column gene_id --rank-column stat -o results
```

Run `dqGSEA --help` for all options.

## Outputs

The default `results` directory contains:

- `gsea.csv`: all tested pathways
- `gsea_significant.csv`: pathways passing the adjusted p-value threshold
- `gene_ranks.csv`: the ranked genes supplied to fgsea
- `gsea_plot.png`: significant pathways, when any are found

Positive enrichment is shown in teal (`#077F97`) and negative enrichment in
purple (`#400257`).

## Input expectations

The DGE table must contain:

- `stat`, or another numeric column selected with `--rank-column`
- `gene_symbol`, `gene_id`, or a column selected with `--gene-column`

The GMT file and selected DGE gene column must use the same identifier type.
