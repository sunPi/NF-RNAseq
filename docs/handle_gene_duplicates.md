# Duplicate gene-symbol handling

`lib/handle_gene_dups.R` is an embedded, base-R expression utility adapted
from `handleGeneDups` 0.1.0. It resolves repeated gene symbols after Ensembl
identifiers have been mapped to gene names.

The default strategy is `highest`, which retains the duplicated row with the
largest total expression across the cohort:

```bash
Rscript lib/handle_gene_dups.R \
  --input annotated_TPM.tsv \
  --output gene_symbol_TPM.tsv
```

Alternative strategies are `mean`, which averages sample values across
duplicated rows, and `suffix`, which keeps all rows with unique suffixes.
Pseudogene removal is optional and disabled by default.

The canonical Ensembl-ID raw-count matrix remains unchanged. Selecting the
highest-expression row provides a unique-symbol representation without adding
unrelated loci or averaging away a strong signal. Mean remains available as an
explicit alternative for analyses that require it.

The embedded source is distributed under the MIT license recorded in
`lib/handleGeneDups.LICENSE`.
