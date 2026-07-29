# Optional-module runtime contract

Each optional module provides `install.sh`, `module.config`, and the runtime
entry point required by its scope.

```bash
MODULE_SCOPE=sample|cohort|hybrid
MODULE_REQUIRES_DESIGN=true|false
MODULE_REQUIRES_CONTRASTS=true|false
MODULE_OUTPUT_NAME=optional_output_directory
```

- `sample`: `run_module.sh` is called once for each QC-included sample.
- `cohort`: `run_cohort.sh` is called once for the complete experiment.
- `hybrid`: `run_module.sh` is called per sample and
  `aggregate_module.py` is then called across the experiment.
- `MODULE_OUTPUT_NAME` optionally overrides the generated results-directory
  name without changing the lowercase module identifier used by `--modules`
  and installation. It must be a single safe path component.

`run_cohort.sh` receives:

```text
--results-dir
--matrix-dir
--output-dir
--samples-file
--assembly
--db-root
--threads
```

When supplied by the user, it also receives `--design`, `--contrasts-file`,
and each repeatable `--contrast` value. The design and contrasts paths refer
to files validated by the core `lib/design_parser.py` function under
`results/EXPERIMENT/design/`.
