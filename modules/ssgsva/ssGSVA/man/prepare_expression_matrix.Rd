\name{prepare_expression_matrix}
\alias{prepare_expression_matrix}
\title{Read and Validate an Expression Matrix}
\usage{
prepare_expression_matrix(path)
}
\arguments{
\item{path}{Path to a CSV, TSV, XLS, or XLSX expression matrix.}
}
\value{A numeric matrix with genes in rows and samples in columns.}
\description{
Reads and validates an expression matrix. Gene identifiers must already be
unique; duplicate identifiers should be resolved with \code{handleGeneDups}
before running ssGSVA.
}
