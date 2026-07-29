#!/usr/bin/env Rscript

usage <- function(status = 0L) {
  cat(
    "ssGSVA - single-sample pathway enrichment\n\n",
    "Usage:\n",
    "  ssGSVA -m EXPRESSION_MATRIX -g GENE_SETS_GMT [options]\n\n",
    "Required:\n",
    "  -m, --matrix FILE       Expression matrix (genes x samples)\n",
    "  -g, --gmt FILE          Gene sets in GMT format\n\n",
    "Options:\n",
    "  -o, --output DIR        Output directory [results]\n",
    "      --method NAME       ssgsea, gsva, or both [both]\n",
    "  -e, --design FILE       Optional sample design table\n",
    "  -v, --verbose           Show GSVA progress messages\n",
    "  -h, --help              Show this help\n",
    "  -V, --version           Show version\n",
    sep = ""
  )
  quit(status = status)
}

parse_arguments <- function(args) {
  options <- list(
    matrix = NULL, gmt = NULL, output = "results",
    method = "both", design = NULL, verbose = FALSE
  )
  aliases <- c(
    "-m" = "matrix", "--matrix" = "matrix",
    "-g" = "gmt", "--gmt" = "gmt",
    "-o" = "output", "--output" = "output",
    "--method" = "method",
    "-e" = "design", "--design" = "design"
  )

  index <- 1L
  while (index <= length(args)) {
    argument <- args[[index]]
    if (argument %in% c("-h", "--help")) usage()
    if (argument %in% c("-V", "--version")) {
      cat("ssGSVA 2.0.0\n")
      quit(status = 0L)
    }
    if (argument %in% c("-v", "--verbose")) {
      options$verbose <- TRUE
      index <- index + 1L
      next
    }
    if (!argument %in% names(aliases)) {
      stop("Unknown option: ", argument, call. = FALSE)
    }
    if (index == length(args)) {
      stop("Missing value for ", argument, call. = FALSE)
    }
    options[[aliases[[argument]]]] <- args[[index + 1L]]
    index <- index + 2L
  }

  if (is.null(options$matrix) || is.null(options$gmt)) {
    stop("Both --matrix and --gmt are required. Run ssGSVA --help.", call. = FALSE)
  }
  options
}

script_file <- grep("^--file=", commandArgs(), value = TRUE)
script_dir <- if (length(script_file)) {
  dirname(normalizePath(sub("^--file=", "", script_file[[1L]])))
} else {
  getwd()
}
source(file.path(script_dir, "R", "ssgsva.R"))

tryCatch({
  options <- parse_arguments(commandArgs(trailingOnly = TRUE))
  run_ssgsva(
    matrix_path = options$matrix,
    gmt_path = options$gmt,
    output_dir = options$output,
    method = options$method,
    design_path = options$design,
    verbose = options$verbose
  )
}, error = function(error) {
  message("Error: ", conditionMessage(error))
  quit(status = 1L)
})
