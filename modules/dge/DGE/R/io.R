read_dge_table <- function(path) {
  if (!file.exists(path)) stop("File does not exist: ", path)
  sep <- if (grepl("\\.(tsv|txt)$", path, ignore.case = TRUE)) "\t" else ","
  utils::read.table(path, header = TRUE, sep = sep, check.names = FALSE,
                    stringsAsFactors = FALSE, comment.char = "", quote = "\"")
}

#' Validate and align DGE inputs
#' @param counts Count data frame.
#' @param design Experiment-design data frame.
#' @param gene_column,sample_column,condition_column Column names.
#' @param reference Reference condition.
#' @param test Test condition. May be omitted for a two-group design.
#' @param min_total_count Minimum total count required per gene.
#' @param input_type raw_counts or normalized.
#' @return Validated counts, design, reference, and test.
#' @export
prepare_dge_inputs <- function(
    counts, design, gene_column = "gene_id", sample_column = "sample_id",
    condition_column = "condition", reference, test = NULL,
    min_total_count = 10L, input_type = c("raw_counts", "normalized")) {
  input_type <- match.arg(input_type)
  missing_counts <- setdiff(gene_column, names(counts))
  missing_design <- setdiff(c(sample_column, condition_column), names(design))
  if (length(missing_counts)) stop("Counts are missing column: ", gene_column)
  if (length(missing_design))
    stop("Design is missing columns: ", paste(missing_design, collapse = ", "))

  genes <- trimws(as.character(counts[[gene_column]]))
  if (anyNA(genes) || any(!nzchar(genes))) stop("Gene identifiers cannot be missing")
  if (anyDuplicated(genes)) stop("Gene identifiers must be unique; run handleGeneDups first")
  matrix_data <- counts[setdiff(names(counts), gene_column)]
  if (!ncol(matrix_data)) stop("Counts contain no sample columns")
  numeric_counts <- suppressWarnings(as.matrix(
    data.frame(lapply(matrix_data, as.numeric), check.names = FALSE)))
  if (anyNA(numeric_counts) && any(!is.na(as.matrix(matrix_data))))
    stop("Count matrix contains non-numeric values")
  if (any(!is.finite(numeric_counts))) stop("Expression values must be finite")
  if (input_type == "raw_counts") {
    if (any(numeric_counts < 0)) stop("Raw counts must be non-negative")
    if (any(abs(numeric_counts - round(numeric_counts)) >
            .Machine$double.eps^0.5))
      stop("Count-based methods require raw integer counts")
    storage.mode(numeric_counts) <- "integer"
  } else {
    storage.mode(numeric_counts) <- "double"
  }
  rownames(numeric_counts) <- genes

  sample_ids <- trimws(as.character(design[[sample_column]]))
  if (anyNA(sample_ids) || any(!nzchar(sample_ids)) || anyDuplicated(sample_ids))
    stop("Design sample identifiers must be present and unique")
  count_samples <- colnames(numeric_counts)
  absent_design <- setdiff(count_samples, sample_ids)
  absent_counts <- setdiff(sample_ids, count_samples)
  if (length(absent_design) || length(absent_counts)) {
    stop("Counts/design sample mismatch. Missing from design: ",
         paste(absent_design, collapse = ", "), "; missing from counts: ",
         paste(absent_counts, collapse = ", "))
  }
  design <- design[match(count_samples, sample_ids), , drop = FALSE]
  rownames(design) <- design[[sample_column]]
  condition <- factor(as.character(design[[condition_column]]))
  if (!reference %in% levels(condition)) stop("Reference condition not found: ", reference)
  candidates <- setdiff(levels(condition), reference)
  if (is.null(test)) {
    if (length(candidates) != 1L)
      stop("--test is required when the design contains more than two conditions")
    test <- candidates
  }
  if (!test %in% levels(condition)) stop("Test condition not found: ", test)
  if (identical(test, reference)) stop("Test and reference conditions must differ")
  keep_samples <- condition %in% c(reference, test)
  design <- design[keep_samples, , drop = FALSE]
  numeric_counts <- numeric_counts[, keep_samples, drop = FALSE]
  design$condition <- stats::relevel(droplevels(condition[keep_samples]), ref = reference)
  if ("batch" %in% names(design)) {
    if (anyNA(design$batch) || any(!nzchar(trimws(as.character(design$batch)))))
      stop("The batch column cannot contain missing or empty values")
    design$batch <- droplevels(factor(design$batch))
    if (nlevels(design$batch) < 2L)
      stop("The batch column must contain at least two batch levels")
  }
  keep_genes <- if (input_type == "raw_counts") {
    rowSums(numeric_counts) >= as.integer(min_total_count)
  } else {
    apply(numeric_counts, 1L, function(x) stats::var(x) > 0)
  }
  if (!any(keep_genes)) stop("No genes remain after minimum-total-count filtering")

  list(counts = numeric_counts[keep_genes, , drop = FALSE],
       design = design, reference = reference, test = test,
       genes_before_filter = nrow(numeric_counts),
       genes_after_filter = sum(keep_genes), input_type = input_type)
}
