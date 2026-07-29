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

Process Flow Chart:

<img width="6663" height="2282" alt="NF-RNAseq - Page 1 NF-RNAseq Core Module Workflow(1)" src="https://github.com/user-attachments/assets/2ae62b0f-9409-4b89-be17-ff330d24fa87" />


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
   --input /path/to/fastq \
   --pipeline core

Run single-end data:
 ./main.sh \
   --assembly GRCh38 \
   --layout single \
   --experiment study_01 \
   --input /path/to/fastq \
   --pipeline core

Run the core pipeline followed by all installed optional modules:
 ./main.sh \
   --assembly GRCh38 \
   --layout single \
   --experiment study_01 \
   --input /path/to/fastq \
   --pipeline optional \
   --modules all

Run one or more modules against a previously completed core experiment:
 ./main.sh \
   --assembly GRCh38 \
   --layout single \
   --experiment study_01 \
   --pipeline modules \
   --modules fusion

Add validated sample metadata and one or more directed contrasts:

 ./main.sh \
   --assembly GRCh38 \
   --layout paired \
   --experiment study_01 \
   --pipeline modules \
   --modules dge \
   --design study.design.tsv \
   --contrast condition:treated:control

Results are written below:
 results/<experiment>/

The main outputs include:
 - Per-sample FastQC and fastp reports
 - STAR alignments
 - RSEM gene and isoform results
 - Sample QC classifications
 - ID-level expected-count matrix
 - Annotated `gene_id`, `gene_name`, and `gene_type` count/TPM/FPKM matrices
 - Unique-symbol highest-expression matrices for downstream activity analyses
 - A matrix manifest describing quantifier, value type, annotation, and
   duplicate-symbol handling
 - MultiQC report
 - Experiment run history in `project_info.tsv`

```

Every invocation is appended to `results/<experiment>/project_info.tsv`.
The ledger records the analysis mode and modules, assembly, read layout,
input path, samples, timing, success or failure status, code revision,
executed command, and results path.

### Experimental designs and contrasts

Design-aware cohort modules accept a TSV or CSV file through `--design`. The
file must contain a unique `sample` column and may contain factors and
covariates such as `condition`, `batch`, and `subject`. See
`examples/design.tsv`.

Contrasts are directed and repeatable:

```text
--contrast condition:treated:control
```

This means treated versus control; a positive effect is higher in treated.
After QC, the pipeline verifies that every retained sample occurs exactly once,
filters the design to retained samples in matrix order, and requires at least
two retained samples in each contrast level. Normalized metadata and parsed
contrasts are stored under `results/<experiment>/design/`.

## 4. Optional Modules

The mutable inventory of implemented and planned biological modules is stored
in `config/module_inventory.json` and validated by
`config/module_inventory.schema.json`.

The core expression utilities include `lib/handle_gene_dups.R`, which resolves
duplicate gene symbols using the highest-expression locus by default after annotation.
Canonical Ensembl-ID count matrices are retained unchanged.

The fusion, isoform-aggregation, DGE, ranked GSEA, and sample-level ssGSVA
modules are currently available.
Install the required module before selecting it at runtime:

```
./install_pipe.sh --add-modules fusion --assembly GRCh38
./install_pipe.sh --add-modules isoforms --assembly GRCh38
./install_pipe.sh --add-modules dge --assembly GRCh38
./install_pipe.sh --add-modules gsea --assembly GRCh38
./install_pipe.sh --add-modules ssgsva --assembly GRCh38
```

The module runs STAR-Fusion and Arriba using the trimmed FASTQ files produced
by the core pipeline. Module outputs are written below:

```
results/<experiment>/<sample>/modules/fusion/
```

DGE runs DESeq2 on the canonical annotated integer count matrix. It requires a
design and at least one contrast and writes normalized counts, full and
significant contrast tables, and QC plots below
`results/<experiment>/matrices/DGE/`. A `batch` or `covariate_batch` design
column is included as a model covariate.

Ranked GSEA consumes the complete DGE statistics for every contrast and writes
fgsea results under `results/<experiment>/matrices/GSEA/`.

ssGSVA calculates per-sample ssGSEA and GSVA pathway scores without requiring
a design. When design contrasts are supplied, it also calculates differential
pathway-score statistics under `results/<experiment>/matrices/ssGSVA/`.

Use `--modules all` to run every installed optional module, or provide a
comma-separated selection as more modules become available.

The following modules are planned for future releases and are not included in

Core Module 1.0:
 - Nextflow workflow execution
 - Immune-cell deconvolution Sturm G, Finotello F, List M. Immunedeconv: An R Package for Unified Access to Computational Methods for Estimating Immune Cell Fractions from Bulk RNA-Sequencing Data. Methods Mol Biol. 2020;2120:223-232. doi: 10.1007/978-1-0716-0327-7_16. PMID: 32124323.
 - ssGSEA pathway analysis Barbie, D., Tamayo, P., Boehm, J. et al. Systematic RNA interference reveals that oncogenic KRAS-driven cancers require TBK1. Nature 462, 108–112 (2009). https://doi.org/10.1038/nature08460
 - Transcription-factor activity inference with decoupleR
 - TRUST4 immune-repertoire analysis Song, L., Cohen, D., Ouyang, Z. et al. TRUST4: immune repertoire reconstruction from bulk and single-cell RNA-seq data. Nat Methods 18, 627–630 (2021). https://doi.org/10.1038/s41592-021-01142-2
 - Additional variant-analysis modules
 - DecoupleR Badia-i-Mompel P., Vélez Santiago J., Braunger J., Geiss C., Dimitrov D., Müller-Dott S., Taus P., Dugourd A., Holland C.H., Ramirez Flores R.O. and Saez-Rodriguez J. 2022. decoupleR: Ensemble of computational methods to infer biological activities from omics data. Bioinformatics Advances.   https://doi.org/10.1093/bioadv/vbac016

License
NF-RNAseq is licensed under the [Apache License 2.0](LICENSE). 

Third-party software and downloaded reference resources remain subject to
their respective licenses and terms of use.
