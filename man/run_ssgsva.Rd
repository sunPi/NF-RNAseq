\name{run_ssgsva}
\alias{run_ssgsva}
\title{Run Single-Sample Pathway Enrichment}
\usage{
run_ssgsva(
  matrix_path,
  gmt_path,
  output_dir = "results",
  method = "both",
  design_path = NULL,
  verbose = FALSE
)
}
\arguments{
\item{matrix_path}{Path to an expression matrix.}
\item{gmt_path}{Path to a GMT gene-set file.}
\item{output_dir}{Output directory.}
\item{method}{One of \code{ssgsea}, \code{gsva}, or \code{both}.}
\item{design_path}{Optional sample design table used for validation.}
\item{verbose}{Whether to show GSVA progress.}
}
\value{A named list of score matrices invisibly.}
\description{
Calculates per-sample pathway scores and writes CSV, RDS, and PNG outputs for
each selected method.
}
