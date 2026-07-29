utils::globalVariables(c("pathway", "mean_score", "direction"))

#' Read and validate an expression matrix
#'
#' The first column must contain gene identifiers and subsequent columns must
#' contain numeric expression values for samples. Gene identifiers must already
#' be unique.
#'
#' @param path Path to a CSV, TSV, XLS, or XLSX expression matrix.
#' @return A numeric matrix with genes in rows and samples in columns.
#' @export
prepare_expression_matrix <- function(path) {
  if (!file.exists(path)) {
    stop("Expression matrix not found: ", path, call. = FALSE)
  }
  extension <- tolower(tools::file_ext(path))
  table <- switch(
    extension,
    csv = utils::read.csv(path, check.names = FALSE),
    tsv = utils::read.delim(path, check.names = FALSE),
    txt = utils::read.delim(path, check.names = FALSE),
    xls =,
    xlsx = {
      if (!requireNamespace("readxl", quietly = TRUE)) {
        stop("Package 'readxl' is required for Excel input.", call. = FALSE)
      }
      as.data.frame(readxl::read_excel(path), check.names = FALSE)
    },
    stop("Unsupported matrix format. Use CSV, TSV, TXT, XLS, or XLSX.", call. = FALSE)
  )

  if (ncol(table) < 2L || nrow(table) == 0L) {
    stop("Expression matrix must contain genes and at least one sample.", call. = FALSE)
  }
  genes <- trimws(as.character(table[[1L]]))
  values <- table[-1L]
  numeric_values <- lapply(values, function(column) {
    converted <- suppressWarnings(as.numeric(column))
    invalid <- !is.na(column) & nzchar(trimws(as.character(column))) & is.na(converted)
    if (any(invalid)) {
      stop("Expression sample columns must contain only numeric values.", call. = FALSE)
    }
    converted
  })
  matrix <- as.matrix(as.data.frame(numeric_values, check.names = FALSE))
  rownames(matrix) <- genes
  keep <- !is.na(genes) & nzchar(genes) & rowSums(is.finite(matrix)) > 0L
  matrix <- matrix[keep, , drop = FALSE]

  duplicated_genes <- unique(rownames(matrix)[duplicated(rownames(matrix))])
  if (length(duplicated_genes)) {
    stop(
      "Duplicate gene identifiers detected. Run handleGeneDups before ssGSVA.",
      call. = FALSE
    )
  }
  if (nrow(matrix) == 0L) {
    stop("No usable genes remain in the expression matrix.", call. = FALSE)
  }
  storage.mode(matrix) <- "double"
  matrix
}

read_gene_sets <- function(path) {
  if (!file.exists(path)) stop("GMT file not found: ", path, call. = FALSE)
  collection <- GSEABase::getGmt(path)
  gene_sets <- GSEABase::geneIds(collection)
  if (length(gene_sets) == 0L) stop("GMT file contains no gene sets.", call. = FALSE)
  gene_sets
}

scores_to_table <- function(scores) {
  data.frame(
    SampleID = colnames(scores),
    t(scores),
    row.names = NULL,
    check.names = FALSE
  )
}

write_score_plot <- function(scores, path) {
  summary <- data.frame(
    pathway = rownames(scores),
    mean_score = rowMeans(scores, na.rm = TRUE)
  )
  summary <- summary[order(abs(summary$mean_score), decreasing = TRUE), , drop = FALSE]
  summary <- utils::head(summary, 20L)
  summary$direction <- ifelse(summary$mean_score >= 0, "Positive", "Negative")
  summary$pathway <- factor(summary$pathway, levels = rev(summary$pathway))

  plot <- ggplot2::ggplot(
    summary,
    ggplot2::aes(x = pathway, y = mean_score, fill = direction)
  ) +
    ggplot2::geom_col(width = 0.75) +
    ggplot2::coord_flip() +
    ggplot2::scale_fill_manual(
      values = c(Positive = "#077F97", Negative = "#400257")
    ) +
    ggplot2::labs(
      x = NULL,
      y = "Mean enrichment score",
      fill = "Direction"
    ) +
    ggprism::theme_prism()
  height <- max(5, min(12, 2.5 + 0.32 * nrow(summary)))
  ggplot2::ggsave(path, plot, width = 9, height = height, dpi = 300)
  invisible(plot)
}

validate_design <- function(path, sample_ids) {
  if (is.null(path)) return(invisible(NULL))
  if (!file.exists(path)) stop("Design table not found: ", path, call. = FALSE)
  extension <- tolower(tools::file_ext(path))
  design <- if (extension == "csv") {
    utils::read.csv(path, check.names = FALSE)
  } else {
    utils::read.delim(path, check.names = FALSE)
  }
  if (ncol(design) < 2L) {
    stop("Design table must contain sample and group columns.", call. = FALSE)
  }
  missing <- setdiff(sample_ids, as.character(design[[1L]]))
  if (length(missing)) {
    stop("Design table is missing samples: ", paste(missing, collapse = ", "), call. = FALSE)
  }
  invisible(design)
}

run_one_method <- function(expression, gene_sets, method, verbose) {
  parameter <- if (method == "ssgsea") {
    GSVA::ssgseaParam(expression, gene_sets, normalize = TRUE)
  } else {
    GSVA::gsvaParam(expression, gene_sets)
  }
  GSVA::gsva(parameter, verbose = verbose)
}

#' Run single-sample pathway enrichment
#'
#' @param matrix_path Expression matrix path.
#' @param gmt_path GMT gene-set file.
#' @param output_dir Output directory.
#' @param method One of ssgsea, gsva, or both.
#' @param design_path Optional sample design table used for validation.
#' @param verbose Show GSVA progress.
#' @return A named list of score matrices invisibly.
#' @export
run_ssgsva <- function(matrix_path, gmt_path, output_dir = "results",
                       method = "both", design_path = NULL, verbose = FALSE) {
  method <- tolower(method)
  if (!method %in% c("ssgsea", "gsva", "both")) {
    stop("--method must be ssgsea, gsva, or both.", call. = FALSE)
  }
  expression <- prepare_expression_matrix(matrix_path)
  gene_sets <- read_gene_sets(gmt_path)
  overlap <- intersect(rownames(expression), unique(unlist(gene_sets, use.names = FALSE)))
  if (length(overlap) == 0L) {
    stop("No gene identifiers overlap between the expression matrix and GMT file.", call. = FALSE)
  }
  validate_design(design_path, colnames(expression))

  methods <- if (method == "both") c("ssgsea", "gsva") else method
  collection_name <- tools::file_path_sans_ext(basename(gmt_path))
  results <- list()
  for (current_method in methods) {
    message("Running ", current_method, "...")
    scores <- run_one_method(expression, gene_sets, current_method, verbose)
    method_dir <- file.path(output_dir, current_method)
    dir.create(method_dir, recursive = TRUE, showWarnings = FALSE)
    suffix <- if (current_method == "ssgsea") "ssGSEA" else "gsva"
    stem <- paste0(collection_name, "_", suffix)
    saveRDS(scores, file.path(method_dir, paste0(stem, ".RDS")))
    utils::write.csv(
      scores_to_table(scores),
      file.path(method_dir, paste0(stem, ".csv")),
      row.names = FALSE
    )
    write_score_plot(scores, file.path(method_dir, paste0(stem, "_plot.png")))
    results[[current_method]] <- scores
  }
  message("Completed ", paste(methods, collapse = " and "), " for ",
          ncol(expression), " samples.")
  invisible(results)
}
