# GRCh38 HPC installation

This installation path targets a Linux x86_64 HPC login node. Run the
installer from an interactive login or installation allocation; reference
construction is not submitted through SLURM yet.

## Prerequisites

- Bash and Conda/Miniforge available on the login node
- outbound HTTPS access to Conda, Ensembl, GitHub, SILVA when enabled, and
  module resource servers
- a persistent installation directory visible from compute nodes
- sufficient memory for STAR index construction

The installer uses `nf-env` for the RNA-seq workflow and pins R to 4.3.3 to
match `renv.lock`. VEP 116 is isolated in `nf-vep-env` so its Perl and HTS
dependency stack cannot downgrade or otherwise constrain core RNA-seq tools.

## Phase 1: core and GRCh38 references

```bash
git clone https://github.com/sunPi/NF-RNAseq.git
cd NF-RNAseq

./install_pipe.sh \
  --assembly GRCh38 \
  --threads 16 \
  --skip-rrna
```

Downloads and completed indices are reused when the command is rerun. The
phase installs the core software, VEP and its GRCh38 cache, the Ensembl FASTA
and GTF, gene annotation mapping, and STAR and RSEM references.

## Phase 2: implemented modules

```bash
./install_pipe.sh \
  --assembly GRCh38 \
  --threads 16 \
  --add-modules all
```

Only modules containing an executable `modules/<name>/install.sh` are
selected by `all`; planned inventory entries are not selected.

## Validation

Validation does not download or rebuild resources:

```bash
./install_pipe.sh \
  --assembly GRCh38 \
  --skip-rrna \
  --validate-only

./install_pipe.sh \
  --assembly GRCh38 \
  --add-modules all \
  --validate-only
```

The core validator checks the active Conda tools, Perl modules, pinned R
version, VEP executable and cache, FASTA/GTF, gene annotation, STAR index,
RSEM reference, generated configuration, and runtime repository files. The
module validator checks each assembly-specific configuration and every
absolute resource path recorded in it.

Installation and validation state is recorded in:

```text
db/install_manifest.tsv
```

## Compute-node check

After installation, start an interactive compute allocation, mount the same
repository path, and run both validation commands again. This detects Conda,
filesystem, executable-bit, and shared-path differences between login and
compute nodes before processing FASTQ files.

SLURM execution support will be added separately; it will consume this same
validated installation and reference contract.
