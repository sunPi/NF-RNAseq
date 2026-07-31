# Gene Ontology module

This cohort module performs ranked Gene Ontology enrichment for every validated
DGE contrast using `clusterProfiler::gseGO`. It tests Biological Process (BP),
Cellular Component (CC), and Molecular Function (MF) terms with HUGO-symbol
rankings from DGE log2 fold changes.

Install it with:

```bash
./install_pipe.sh --add-modules go --assembly GRCh38
```

Run DGE and GO together:

```bash
./main.sh --assembly GRCh38 --layout single --experiment EXPERIMENT \
  --pipeline modules --modules dge,go --design design.tsv \
  --contrast condition:KO:WT
```

Results are written to `results/EXPERIMENT/matrices/GO/contrasts/CONTRAST_ID`.
GO can also be run alone when matching DGE contrast results already exist.
