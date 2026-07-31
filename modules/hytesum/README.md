# HyTEsum module

This cohort module implements the `analyse_HyTEsum` workflow using the Hypoxia,
TGF-beta signaling, and epithelial-mesenchymal-transition Hallmark signatures.
It scores the complete pinned Hallmark collection for compatibility with the
legacy workflow, then extracts the three components and calculates their raw
HyTEsum, a cohort-normalized zero-to-one index, and a median High/Low split.

```bash
./install_pipe.sh --add-modules hytesum --assembly GRCh38
./main.sh --assembly GRCh38 --layout single --experiment EXPERIMENT \
  --pipeline modules --modules hytesum
```

The module is standalone and does not require a design. When a design is
supplied, it also writes a joined score/design table.
