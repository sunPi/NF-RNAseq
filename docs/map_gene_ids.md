# Gene identifier annotation

`lib/map_gene_ids.py` adapts the `mapGeneID` utility for reproducible,
assembly-specific NF-RNAseq matrices. Instead of querying the changing live
BioMart service, it builds a cache from the exact Ensembl GTF installed with
the pipeline.

During installation, the cache is written to:

```text
db/homo_sapiens/ASSEMBLY/annotation/gene_annotation.tsv
```

It has the canonical structure:

```text
gene_id	gene_name	gene_type
ENSG00000000003	TSPAN6	protein_coding
```

Every completed expression matrix begins with those three fields followed by
sample columns. Ensembl version suffixes are removed. If an identifier is not
present in the installed GTF, its `gene_name` falls back to the Ensembl ID and
its `gene_type` is `unannotated`.

The core pipeline writes two explicit convergence layers:

```text
matrices/expression/
├── gene_counts.tsv                  # integer FeatureCounts
├── gene_rsem_expected_counts.tsv    # fractional RSEM estimates
├── gene_TPM.tsv
└── gene_FPKM.tsv

matrices/annotated/
├── gene_counts.tsv
├── gene_TPM.tsv
├── gene_FPKM.tsv
└── deduplicated/
    ├── gene_counts.highest.tsv
    ├── gene_TPM.highest.tsv
    └── gene_FPKM.highest.tsv
```

The final three files apply `handleGeneDups` after annotation and provide
unique gene-symbol rows by retaining the highest-expression locus. Count-based DGE should use the
uncollapsed annotated or ID-level FeatureCounts matrix; symbol-level
matrices are intended for methods such as ssGSEA and decoupleR.

The embedded adaptation retains the upstream MIT license in
`lib/mapGeneID.LICENSE`.
