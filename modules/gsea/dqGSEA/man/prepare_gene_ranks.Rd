\name{prepare_gene_ranks}
\alias{prepare_gene_ranks}
\title{Prepare a Named, Ranked Gene Vector}
\usage{
prepare_gene_ranks(dge, gene_column = NULL, rank_column = "stat")
}
\arguments{
\item{dge}{A differential-expression results data frame.}
\item{gene_column}{Gene identifier column. When \code{NULL},
\code{gene_symbol} is preferred over \code{gene_id}.}
\item{rank_column}{Numeric ranking column.}
}
\value{A decreasing named numeric vector.}
\description{
Filters unusable values, collapses duplicate gene identifiers by their mean
rank statistic, and sorts the resulting vector.
}
