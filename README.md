# ssGSVA

`ssGSVA` calculates pathway-enrichment scores for each sample in an expression
matrix using ssGSEA, GSVA, or both methods.

## Usage

```bash
ssGSVA -m expression.csv -g pathways.gmt
```

Both methods run by default to preserve compatibility with existing workflows:

```bash
ssGSVA -m expression.csv -g pathways.gmt --method both -o results
```

Run one method only:

```bash
ssGSVA -m expression.csv -g pathways.gmt --method ssgsea
```

The expression matrix must have genes in its first column and samples in the
remaining numeric columns. Gene identifiers must match those in the GMT file.
Gene identifiers must be unique; run `handleGeneDups` before ssGSVA when
duplicates are present.

## Outputs

Results are written under:

- `results/ssgsea/`
- `results/gsva/`

Each selected method produces a CSV score matrix, an RDS score matrix, and a
PNG summary plot. Positive scores are teal (`#077F97`) and negative scores are
purple (`#400257`).

## Optional design validation

A design table can be supplied to confirm that all expression samples are
represented:

```bash
ssGSVA -m expression.csv -g pathways.gmt -e design.csv
```

The first design column contains sample identifiers and the second contains
groups.
