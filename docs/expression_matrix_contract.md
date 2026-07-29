# Expression matrix contract

The core pipeline exposes two stable convergence layers for optional modules.

## ID-level expression

`results/EXPERIMENT/matrices/expression/` contains:

- `gene_counts.tsv`: integer FeatureCounts values from STAR genomic BAMs.
- `gene_rsem_expected_counts.tsv`: fractional RSEM expected counts retained
  for methods that explicitly support abundance estimates.
- `gene_TPM.tsv` and `gene_FPKM.tsv`: continuous RSEM expression values.

All files begin with `gene_id`, followed by QC-included samples in canonical
matrix order.

## Annotated expression

`results/EXPERIMENT/matrices/annotated/` contains `gene_counts.tsv`,
`gene_TPM.tsv`, and `gene_FPKM.tsv` beginning with:

```text
gene_id	gene_name	gene_type
```

The `deduplicated/` directory provides unique-symbol derivatives selected with
the highest total expression across the cohort. No loci are summed or
averaged by default.

`results/EXPERIMENT/matrices/matrix_manifest.tsv` records the quantifier, value
type, annotation level, duplicate-symbol policy, and path for every matrix.
Optional modules should select inputs from this manifest instead of inferring
matrix semantics from filenames.

The stages remain independently executable:

1. `featureCounts` creates sample-level integer counts from an existing STAR
   genomic BAM.
2. `lib/map_gene_ids.py` annotates an existing ID-level matrix.
3. `lib/handle_gene_dups.R` creates a unique-symbol matrix from an existing
   annotated matrix.
