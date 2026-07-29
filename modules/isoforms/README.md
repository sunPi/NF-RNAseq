# Isoform quantification module

This module aggregates the transcript-level RSEM results produced by the
NF-RNAseq core pipeline. It does not rerun alignment or quantification and
works identically for single- and paired-end experiments.

## Installation

```bash
./install_pipe.sh --add-modules isoforms --assembly GRCh38
```

No additional database is downloaded. Installation writes the module contract
under `db/shared/isoforms_module/config/`.

## Execution

Run the module for an existing completed core experiment:

```bash
./main.sh --assembly GRCh38 --layout paired \
  --experiment EXPERIMENT --pipeline modules --modules isoforms
```

The cohort matrices are written to:

```text
results/EXPERIMENT/matrices/isoforms/
├── transcript_expected_counts.tsv
├── transcript_TPM.tsv
├── transcript_FPKM.tsv
└── transcript_isoform_fraction.tsv
```

Each row contains a `transcript_id`, its parent `gene_id`, and one value per
QC-included sample. `transcript_isoform_fraction.tsv` contains RSEM `IsoPct`,
the percentage of a gene's estimated expression assigned to each transcript.
This is a transcript usage fraction and not splice-junction PSI.

The module is cohort-scoped: it runs once per experiment and does not require
retained FASTQ files in modules-only mode.

An existing experiment can also be aggregated directly:

```bash
python3 modules/isoforms/aggregate_module.py \
  --results-dir results/EXPERIMENT \
  --output-dir results/EXPERIMENT/matrices/isoforms \
  --samples-file results/EXPERIMENT/QC/qc_included_samples.txt
```
