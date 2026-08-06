# TRUST4 module

This hybrid module reconstructs TCR and BCR repertoires from the core analysis
FASTQs. It supports single- and paired-end bulk RNA-seq and uses versioned human
IMGT plus assembly-specific V(D)J references bundled with TRUST4.

Install and run:

```bash
./install_pipe.sh --add-modules trust4 --assembly GRCh38
./main.sh --assembly GRCh38 --layout single --experiment EXPERIMENT \
  --pipeline modules --modules trust4
```

Per-sample TRUST4 reports and AIRR tables are stored below
`results/EXPERIMENT/SAMPLE/modules/TRUST4/`. Cohort clonotype count, frequency,
and catalog tables are stored below `results/EXPERIMENT/matrices/TRUST4/`.
