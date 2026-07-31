# SarSig module

This cohort module implements the intended `computeSarSig` workflow from the
EMT Reversal study. It selects the fixed 63-gene SarSig signature, transforms
TPM as `log2(TPM+1)`, z-scores each gene across all QC-included experiment
samples, and sums those z-scores per sample.

```bash
./install_pipe.sh --add-modules sarsig --assembly GRCh38
./main.sh --assembly GRCh38 --layout single --experiment EXPERIMENT \
  --pipeline modules --modules sarsig
```

A design is optional and adds a joined score/design table. Because gene
z-scores are cohort-relative, scores should be compared only within the same
scoring run.
