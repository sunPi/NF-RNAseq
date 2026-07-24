# NF-RNAseq

## 1. Pipeline Overview

NF-RNAseq is a Linux-based bulk RNA-sequencing pipeline for processing
single-end and paired-end short-read FASTQ files.

The Core Module 1.0 workflow performs:

1. Raw-read quality control with FastQC
2. Adapter trimming and filtering with fastp
3. Quality control of trimmed reads
4. Alignment with STAR
5. BAM indexing with Samtools
6. Gene and transcript quantification with RSEM
7. Sample-level quality assessment
8. Generation of expected-count, TPM, and FPKM matrices
9. Aggregated reporting with MultiQC

Workflow overview:

```
FASTQ
  * FastQC
  * fastp
  * FastQC
  * STAR
  * Samtools
  * RSEM
  * QC validation
  * expression matrices
  * MultiQC
```

## 2. Supported Data

The current release supports bulk short-read RNA sequencing from platforms
such as Illumina and MGI.

Supported read layouts:
* Single-end
* Paired-end
* Supported human reference assemblies:
  - GRCh38/hg38
  - GRCh37/hg19

Paired-end files must follow this naming convention:
 - SAMPLE_1.fastq.gz
 - SAMPLE_2.fastq.gz

Single-end input should use:
 - SAMPLE.fastq.gz

The .fq.gz extension is also supported. Input directories are searched
recursively. The current release does not support long-read or single-cell RNA sequencing.




Installation:

Run `Rscript setup/scripts/initialize_renv.R` to initialize the renv

This is a base version of the RNAseq pipeline currently doing the following:

<img width="1158" height="327" alt="image" src="https://github.com/user-attachments/assets/ffa572bf-1cd9-4333-b865-364b5fc426dd" />

Currently, it supports both single and paired-end sample processing, however is adapted to process only short-read samples (Illumina NovaSEQ, MGI).

Optional modules:

These are modules that are not critical in producing gene expression matrices, but answer biological questions based on them.

- decoupler Badia-i-Mompel P., Vélez Santiago J., Braunger J., Geiss C., Dimitrov D., Müller-Dott S., Taus P., Dugourd A., Holland C.H., Ramirez Flores R.O. and Saez-Rodriguez J. 2022. decoupleR: Ensemble of computational methods to infer biological activities from omics data. Bioinformatics Advances. https://doi.org/10.1093/bioadv/vbac016
- immune deconvolution Sturm G, Finotello F, List M. Immunedeconv: An R Package for Unified Access to Computational Methods for Estimating Immune Cell Fractions from Bulk RNA-Sequencing Data. Methods Mol Biol. 2020;2120:223-232. doi: 10.1007/978-1-0716-0327-7_16. PMID: 32124323.
- ssgsea Barbie, D., Tamayo, P., Boehm, J. et al. Systematic RNA interference reveals that oncogenic KRAS-driven cancers require TBK1. Nature 462, 108–112 (2009). https://doi.org/10.1038/nature08460
- trust4 Song, L., Cohen, D., Ouyang, Z. et al. TRUST4: immune repertoire reconstruction from bulk and single-cell RNA-seq data. Nat Methods 18, 627–630 (2021). https://doi.org/10.1038/s41592-021-01142-2

## 3. Installation

Requirements

```
* Linux
* Bash
* Conda, Miniconda, Miniforge, or Mambaforge
* Internet access during installation
* Sufficient storage and memory for genome-reference construction
```

Download

```

git clone https://github.com/sunPi/NF-RNAseq.git
cd NF-RNAseq

```

Install

```

Install GRCh38:
./install_pipe.sh --assembly GRCh38 --threads 16

Install GRCh37/hg19:
./install_pipe.sh --assembly hg19 --threads 16

Install both assemblies:
./install_pipe.sh --with-hg19 --threads 16

The installer creates the nf-env Conda environment, restores R packages
from renv.lock, downloads reference resources, constructs the STAR and RSEM
indices, and generates the local config/main.config.

Activate the environment:
conda activate nf-env
```

Run

```

Run paired-end data:
./main.sh \
  --assembly GRCh38 \
  --layout paired \
  --experiment study_01 \
  --input /path/to/fastq
Run single-end data:
./main.sh \
  --assembly GRCh38 \
  --layout single \
  --experiment study_01 \
  --input /path/to/fastq
Results are written below:
results/<experiment>/
The main outputs include:
Per-sample FastQC and fastp reports
STAR alignments
RSEM gene and isoform results
Sample QC classifications
Expected-count matrix
TPM matrix

```

FPKM matrix
MultiQC report
