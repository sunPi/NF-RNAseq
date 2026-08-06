# Telescope module

This hybrid module estimates locus-specific HERV and LINE-1 expression from the
core STAR genomic BAM. The coordinate-sorted BAM is temporarily name-collated,
as required by Telescope, while preserving STAR multimapping alignments.

Install and run:

```bash
./install_pipe.sh --add-modules telescope --assembly GRCh38
./main.sh --assembly GRCh38 --layout single --experiment EXPERIMENT \
  --pipeline modules --modules telescope
```

The installer pins Telescope and its official annotation database revisions.
It applies two minimal Python 3 build/runtime compatibility fixes to the pinned
upstream source (package-qualified Cython import and universal-newline mode).
GRCh38 uses the combined `retro.hg38.v1` HERV/LINE-1 annotation. GRCh37 combines
the official `HERV_rmsk.hg19.v2` and `L1Base.hg19.v1` annotations.

Per-sample assignment outputs are stored below
`results/EXPERIMENT/SAMPLE/modules/Telescope/`; the cohort locus-count matrix is
`results/EXPERIMENT/matrices/Telescope/telescope_locus_counts.tsv`.
