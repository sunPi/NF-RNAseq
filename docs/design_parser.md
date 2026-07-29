# Design parser

The design parser is internal NF-RNAseq infrastructure. It validates
sample metadata and directed contrasts before cohort analyses such as DGE,
GSEA, differential transcript usage, differential splicing, and differential
regulator activity.

It is invoked automatically when `main.sh` receives `--design`. It is part of
the pipeline's core function set, not an optional biological module.

## Design format

The input may be tab- or comma-separated and must contain a unique `sample`
column. Other columns represent experimental factors or covariates:

```text
sample	condition	batch	subject
sample_01	control	batch1	P01
sample_02	control	batch2	P02
sample_03	treated	batch1	P03
sample_04	treated	batch2	P04
```

Contrasts use `FACTOR:NUMERATOR:DENOMINATOR`. For example,
`condition:treated:control` means treated versus control, so a positive effect
represents a higher value in treated samples.

## Pipeline usage

```bash
./main.sh --assembly GRCh38 --layout paired \
  --experiment study_01 --pipeline modules --modules dge \
  --design study.design.tsv \
  --contrast condition:treated:control
```

The parser filters and orders the design using the QC-included sample list,
validates contrast levels and replicates, and writes:

```text
results/study_01/design/design.tsv
results/study_01/design/contrasts.tsv
```

## Standalone usage

```bash
python3 lib/design_parser.py \
  --design examples/design.tsv \
  --samples-file results/study_01/QC/qc_included_samples.txt \
  --output-design results/study_01/design/design.tsv \
  --output-contrasts results/study_01/design/contrasts.tsv \
  --contrast condition:treated:control
```
