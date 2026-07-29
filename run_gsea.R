#!/usr/bin/env Rscript

usage <- function(status = 0L) {
  cat(
    "dqGSEA - preranked gene set enrichment analysis\n\n",
    "Usage:\n  dqGSEA -d DGE_TABLE -g PATHWAYS_GMT [options]\n\n",
    "Required:\n",
    "  -d, --dge FILE          DGE results table (CSV or TSV)\n",
    "  -g, --gmt FILE          Gene sets in GMT format\n\n",
    "Options:\n",
    "  -o, --output DIR        Output directory [results]\n",
    "  -p, --padj NUMBER       Adjusted p-value threshold [0.05]\n",
    "      --gene-column NAME  Gene identifier column [gene_symbol, then gene_id]\n",
    "      --rank-column NAME  Ranking statistic column [stat]\n",
    "      --min-size NUMBER   Minimum pathway size [10]\n",
    "      --max-size NUMBER   Maximum pathway size [500]\n",
    "  -h, --help              Show this help\n",
    sep = ""
  )
  quit(status = status)
}

parse_arguments <- function(args) {
  options <- list(dge = NULL, gmt = NULL, output = "results", padj = 0.05,
                  gene_column = NULL, rank_column = "stat",
                  min_size = 10L, max_size = 500L)
  aliases <- c("-d" = "dge", "--dge" = "dge", "-g" = "gmt", "--gmt" = "gmt",
               "-o" = "output", "--output" = "output", "-p" = "padj",
               "--padj" = "padj", "--gene-column" = "gene_column",
               "--rank-column" = "rank_column", "--min-size" = "min_size",
               "--max-size" = "max_size")
  index <- 1L
  while (index <= length(args)) {
    argument <- args[[index]]
    if (argument %in% c("-h", "--help")) usage()
    if (!argument %in% names(aliases)) stop("Unknown option: ", argument, call. = FALSE)
    if (index == length(args)) stop("Missing value for ", argument, call. = FALSE)
    options[[aliases[[argument]]]] <- args[[index + 1L]]
    index <- index + 2L
  }
  if (is.null(options$dge) || is.null(options$gmt)) {
    stop("Both --dge and --gmt are required. Run dqGSEA --help.", call. = FALSE)
  }
  options$padj <- as.numeric(options$padj)
  options$min_size <- as.integer(options$min_size)
  options$max_size <- as.integer(options$max_size)
  options
}

script_file <- grep("^--file=", commandArgs(), value = TRUE)
script_dir <- if (length(script_file)) {
  dirname(normalizePath(sub("^--file=", "", script_file[[1L]])))
} else {
  getwd()
}
source(file.path(script_dir, "R", "dqgsea.R"))

tryCatch({
  options <- parse_arguments(commandArgs(trailingOnly = TRUE))
  run_dqgsea(
    dge_path = options$dge, gmt_path = options$gmt,
    output_dir = options$output, padj_threshold = options$padj,
    gene_column = options$gene_column, rank_column = options$rank_column,
    min_size = options$min_size, max_size = options$max_size
  )
}, error = function(error) {
  message("Error: ", conditionMessage(error))
  quit(status = 1L)
})
