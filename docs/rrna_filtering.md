# rRNA core phase

The installer prepares a combined SILVA SSU/LSU NR99 FASTA and Bowtie2 index.
New installations enable this core phase by default; pass `--skip-rrna` to
`install_pipe.sh` to disable both reference preparation and runtime filtering.

At runtime, rRNA filtering occurs after `fastp` and before analysis-read FastQC
and STAR alignment. Single-end reads use Bowtie2 `--un-gz`. Paired-end reads use
`--un-conc-gz`, preserving complete pairs that do not align concordantly to the
rRNA reference. The retained FASTQs are written to:

- `results/EXPERIMENT/SAMPLE/rrna/SAMPLE_non_rRNA.fastq.gz` for single-end data
- `results/EXPERIMENT/SAMPLE/rrna/SAMPLE_non_rRNA_R1.fastq.gz` and `_R2.fastq.gz`
  for paired-end data

STAR and FASTQ-level optional modules use these retained reads. If rRNA
filtering was disabled, they use the `fastp` outputs instead. The exact paths
used by the core are recorded in `results/EXPERIMENT/QC/core_read_manifest.tsv`.

Per-sample fragment counts and the removed percentage are saved below each
sample's `rrna/` directory. The combined table is
`results/EXPERIMENT/QC/rRNA_summary.tsv`, and the rRNA rate is included in the
standard QC reports when filtering ran.

Validate an installed SILVA reference with:

```bash
./install_pipe.sh --assembly GRCh38 --validate-only
```
