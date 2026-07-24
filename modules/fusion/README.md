# Fusion detection module

This module adapts the previous RNA-seq pipeline's dual fusion-calling
strategy:

- **STAR-Fusion** runs directly from trimmed FASTQ files using a
  CTAT genome library.
- **FusionInspector** remaps reads to candidate fusion contigs, validates the
  candidates, and estimates fusion-supporting abundance as FFPM.
- **Arriba** runs from a dedicated STAR alignment configured to retain
  chimeric reads.

The dedicated Arriba alignment is intentional. The core pipeline's expression
alignment is not currently generated with all chimeric-read settings required
by Arriba.

## Requirements

- Single- or paired-end, gzip-compressed FASTQ files
- `STAR-Fusion`, `FusionInspector`, `STAR`, and `arriba` available on `PATH`
- An assembly-matched CTAT genome library containing:
  - `ref_genome.fa`
  - `ref_annot.gtf`
  - `ref_genome.fa.star.idx/`
- Assembly-matched Arriba blacklist, known-fusion, and protein-domain files
  are strongly recommended

## Example

```bash
modules/fusion/run_fusion.sh \
  --sample SAMPLE_01 \
  --layout paired \
  --read1 results/experiment/SAMPLE_01/fastp/SAMPLE_01_trimmed_R1.fastq.gz \
  --read2 results/experiment/SAMPLE_01/fastp/SAMPLE_01_trimmed_R2.fastq.gz \
  --output-dir results/experiment/SAMPLE_01/fusion \
  --ctat-genome-lib /references/GRCh38_gencode_CTAT_lib/ctat_genome_lib_build_dir \
  --arriba-blacklist /references/arriba/blacklist_hg38_GRCh38.tsv.gz \
  --arriba-known-fusions /references/arriba/known_fusions_hg38_GRCh38.tsv.gz \
  --arriba-protein-domains /references/arriba/protein_domains_hg38_GRCh38.gff3 \
  --star-fusion-executable /references/fusion/tools/STAR-Fusion \
  --fusion-inspector-executable /references/fusion/tools/STAR-Fusion-v1.15.1/FusionInspector/FusionInspector \
  --threads 8
```

Use `--caller star-fusion` or `--caller arriba` to run only one caller.

For single-end data, pass `--layout single` and omit `--read2`. When called
from the main pipeline, the module receives the pipeline's existing
`READ_LAYOUT` value rather than requiring a second layout choice from the
user.

## Outputs

For STAR-Fusion:

```text
OUTPUT_DIR/star-fusion/star-fusion.fusion_predictions.tsv
OUTPUT_DIR/star-fusion/SAMPLE.star-fusion.fusion_genes.tsv
```

For FusionInspector:

```text
OUTPUT_DIR/fusion-inspector/SAMPLE.FusionInspector.fusions.abridged.tsv
```

For Arriba:

```text
OUTPUT_DIR/arriba/fusions.tsv
OUTPUT_DIR/arriba/fusions.discarded.tsv
OUTPUT_DIR/arriba/SAMPLE.arriba.fusion_genes.tsv
```

The sample-specific tables prepend a `Sample` column and are suitable for
later experiment-level aggregation.

## Experiment-level fusion matrices

Create a tab-delimited manifest:

```text
sample	fusion_inspector
SAMPLE_01	/path/SAMPLE_01.FusionInspector.fusions.abridged.tsv
SAMPLE_02	/path/SAMPLE_02.FusionInspector.fusions.abridged.tsv
```

Then run:

```bash
python3 modules/fusion/aggregate_fusions.py \
  --manifest fusion_manifest.tsv \
  --output-dir results/experiment/fusion/matrices
```

This produces breakpoint-specific matrices for:

- junction-read counts;
- spanning-fragment counts;
- total supporting fragments;
- FFPM fusion-transcript abundance.

Breakpoint coordinates are included in each row identifier because the same
gene pair can have multiple fusion transcript breakpoints.

The optional-module installation entry point is:

```bash
./install_pipe.sh --add-modules fusion --assembly GRCh38
```

The dispatcher calls this module's `install.sh`. Fusion reference assets are
stored below `db/shared/fusion_module/`, with assembly-specific subdirectories
for files that must match GRCh37 or GRCh38.

The CTAT plug-and-play libraries are approximately 33–36 GB compressed and
require substantially more temporary disk space during extraction. Downloads
are resumable and retained in `db/shared/fusion_module/downloads/`.

The installer writes the resolved runtime paths to:

```text
db/shared/fusion_module/config/GRCh37.config
db/shared/fusion_module/config/GRCh38.config
```

Set `FUSION_CTAT_URL` or `FUSION_ARRIBA_URL` to use an internal mirror.

On `linux-aarch64`, STAR-Fusion is installed from its official FULL release
because its Bioconda dependency stack is not currently solvable for that
platform. On `linux-x86_64`, the installer uses Bioconda. The generated
configuration records the resolved executable path.

The ARM build compiles only STAR-Fusion's required Perl plugin. It does not
build the bundled optional FusionInspector component, whose additional R
dependencies are not used by this module. A generated wrapper keeps the ARM
build on the system Perl ABI; the amd64 production installation remains fully
Conda-managed.
