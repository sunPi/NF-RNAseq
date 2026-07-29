dge_usage <- function() paste(
  "Differential gene expression with DESeq2 or limma",
  "",
  "Usage:",
  "  DGE -d COUNTS -e DESIGN -r REFERENCE [options]",
  "",
  "Required:",
  "  -d, --data FILE             Count or normalized expression matrix",
  "  -e, --design FILE           Experiment design",
  "  -r, --reference NAME        Reference condition",
  "",
  "Options:",
  "  -t, --test NAME             Test condition [inferred for two groups]",
  "  -o, --output DIR            Output directory [results]",
  "  -p, --padj NUMBER           Adjusted-P threshold [0.05]",
  "  -n, --normalised            Use limma for normalized expression",
  "      --lfc NUMBER            Absolute log2-fold-change threshold [1]",
  "      --min-total-count N     Count-method gene filter [10]",
  "      --gene-column NAME      Gene-ID column [gene_id]",
  "      --sample-column NAME    Design sample column [sample_id]",
  "      --condition-column NAME Design condition column [condition]",
  "      --no-annotation         Do not map human ENSEMBL IDs to symbols",
  "  -v, --verbose               Print progress",
  "  -V, --version               Print version",
  "  -h, --help                  Show this help", sep = "\n")

parse_dge_args <- function(args) {
  aliases <- c("-d" = "--data", "-e" = "--design", "-r" = "--reference",
               "-t" = "--test", "-o" = "--output", "-p" = "--padj")
  args <- unname(ifelse(args %in% names(aliases), aliases[args], args))
  value <- function(flag, default = NULL) {
    i <- match(flag, args)
    if (is.na(i)) return(default)
    if (i == length(args) || startsWith(args[i + 1L], "-"))
      stop("Missing value for ", flag)
    args[i + 1L]
  }
  list(data = value("--data"), design = value("--design"),
       reference = value("--reference"), test = value("--test"),
       output = value("--output", "results"),
       padj = as.numeric(value("--padj", "0.05")),
       lfc = as.numeric(value("--lfc", "1")),
       min_total_count = as.integer(value("--min-total-count", "10")),
       gene_column = value("--gene-column", "gene_id"),
       sample_column = value("--sample-column", "sample_id"),
       condition_column = value("--condition-column", "condition"),
       annotate = !("--no-annotation" %in% args),
       normalised = any(c("-n", "--normalised", "--normalized") %in% args),
       verbose = any(c("-v", "--verbose") %in% args))
}

#' DGE command-line interface
#' @param args Command-line arguments.
#' @return Invisibly, generated paths.
#' @export
dge_cli <- function(args = commandArgs(trailingOnly = TRUE)) {
  if (!length(args) || any(c("-h", "--help") %in% args)) {
    cat(dge_usage(), "\n")
    return(invisible(NULL))
  }
  if (any(c("-V", "--version") %in% args)) {
    cat("runDGE 0.3.0\n")
    return(invisible(NULL))
  }
  config <- parse_dge_args(args)
  required <- c("data", "design", "reference")
  absent <- required[vapply(config[required], is.null, logical(1))]
  if (length(absent))
    stop("Missing required arguments: ", paste(absent, collapse = ", "),
         "\n\n", dge_usage())
  if (config$verbose) message("Reading and validating DGE inputs")
  input_type <- if (config$normalised) "normalized" else "raw_counts"
  prepared <- prepare_dge_inputs(
    read_dge_table(config$data), read_dge_table(config$design),
    config$gene_column, config$sample_column, config$condition_column,
    config$reference, config$test, config$min_total_count, input_type)
  if (config$verbose)
    message("Running ", prepared$test, " vs ", prepared$reference,
            " with ", if (config$normalised) "limma" else "DESeq2",
            if ("batch" %in% names(prepared$design)) " (batch-adjusted)" else "")
  result <- if (config$normalised) {
    run_limma_dge(prepared, config$padj, config$lfc, config$annotate)
  } else {
    run_dge(prepared, config$padj, config$lfc, config$annotate)
  }
  paths <- write_dge_results(result, config$output)
  message("DGE results written to ", normalizePath(config$output))
  invisible(paths)
}
