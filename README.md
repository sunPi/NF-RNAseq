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
tomated RNA-seq pipeline that produces analysis-ready data in the form of gene expression matrices, where it uses FASTQ files as inputs.

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
