# decoupleR module

The `decoupler` cohort module infers regulator activities from the canonical
unique-HUGO TPM matrix.

- CollecTRI transcription-factor activities: vectorized ULM, numerically
  equivalent to decoupleR's independent linear-model statistic
- PROGENy pathway activities: MLM, top 500 responsive genes
- Sample activities: all QC-included experiment samples
- Differential activities: only samples and contrasts supplied by the design

Install and run:

```bash
./install_pipe.sh --add-modules decoupler --assembly GRCh38
./main.sh --assembly GRCh38 --layout single --experiment EXPERIMENT \
  --pipeline modules --modules decoupler
```

Add `--design` and `--contrast FACTOR:NUMERATOR:DENOMINATOR` to generate
differential regulator-activity tables and waterfall plots.

The implementation filters expression to each network's targets, respects the
pipeline thread limit, writes a checkpoint after each resource, and reuses
current activity matrices on subsequent module runs.
