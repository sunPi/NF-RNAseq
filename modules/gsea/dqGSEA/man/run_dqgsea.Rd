\name{run_dqgsea}
\alias{run_dqgsea}
\title{Run Preranked Gene Set Enrichment Analysis}
\usage{
run_dqgsea(
  dge_path,
  gmt_path,
  output_dir = "results",
  padj_threshold = 0.05,
  gene_column = NULL,
  rank_column = "stat",
  min_size = 10L,
  max_size = 500L
)
}
\arguments{
\item{dge_path}{Path to a DGE results table.}
\item{gmt_path}{Path to a GMT pathway file.}
\item{output_dir}{Output directory.}
\item{padj_threshold}{Adjusted p-value threshold.}
\item{gene_column}{Optional gene identifier column.}
\item{rank_column}{Numeric ranking column.}
\item{min_size}{Minimum pathway size.}
\item{max_size}{Maximum pathway size.}
}
\value{The complete fgsea results invisibly.}
\description{
Prepares gene ranks, runs fgsea, and writes full and significant pathway
results, gene ranks, and a plot when significant pathways are present.
}
