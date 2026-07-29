#!/usr/bin/env Rscript

# Embedded from handleGeneDups 0.1.0 and adapted for NF-RNAseq TSV matrices.
# Copyright (c) 2026 Jan Rogel A and CBC Labs. Licensed under the MIT License.

`%||%` <- function(left, right) {
  if (length(left) && !is.na(left)) left else right
}

handle_gene_duplicates <- function(
    data,
    gene_col = "gene_name",
    strategy = c("highest", "mean", "suffix"),
    expression_cols = NULL,
    id_col = "gene_id",
    type_col = "gene_type",
    remove_pseudogenes = FALSE,
    na_action = c("error", "drop", "keep", "zero"),
    round_digits = NULL,
    suffix_sep = "_dup"
) {
  strategy <- match.arg(strategy)
  na_action <- match.arg(na_action)

  if (!is.data.frame(data)) {
    stop("Input must be a data frame.", call. = FALSE)
  }
  if (length(gene_col) != 1L || !gene_col %in% names(data)) {
    stop(sprintf("Gene column is missing: %s", gene_col), call. = FALSE)
  }

  result <- data
  if (remove_pseudogenes) {
    if (is.null(type_col) || !type_col %in% names(result)) {
      stop("A gene-type column is required to remove pseudogenes.", call. = FALSE)
    }
    is_pseudogene <- grepl("pseudogene", result[[type_col]], ignore.case = TRUE)
    is_pseudogene[is.na(is_pseudogene)] <- FALSE
    result <- result[!is_pseudogene, , drop = FALSE]
  }

  metadata_cols <- Filter(Negate(is.null), list(id_col, gene_col, type_col))
  if (is.null(expression_cols)) {
    candidates <- setdiff(names(result), metadata_cols)
    expression_cols <- candidates[
      vapply(result[candidates], is.numeric, logical(1))
    ]
  }
  if (!length(expression_cols) || !all(expression_cols %in% names(result))) {
    stop("No valid expression columns were selected.", call. = FALSE)
  }
  if (!all(vapply(result[expression_cols], is.numeric, logical(1)))) {
    stop("All expression columns must be numeric.", call. = FALSE)
  }

  incomplete <- !stats::complete.cases(result[expression_cols])
  if (any(incomplete)) {
    if (na_action == "error") {
      stop("Missing expression values detected.", call. = FALSE)
    }
    if (na_action == "drop") {
      result <- result[!incomplete, , drop = FALSE]
    }
    if (na_action == "zero") {
      for (column in expression_cols) {
        result[[column]][is.na(result[[column]])] <- 0
      }
    }
  }

  if (!anyDuplicated(result[[gene_col]])) {
    rownames(result) <- NULL
    return(result)
  }
  if (strategy == "suffix") {
    result[[gene_col]] <- make.unique(
      as.character(result[[gene_col]]),
      sep = suffix_sep
    )
    rownames(result) <- NULL
    return(result)
  }

  groups <- split(seq_len(nrow(result)), result[[gene_col]])
  first_positions <- vapply(groups, function(rows) rows[[1L]], integer(1))
  groups <- groups[order(first_positions)]
  resolved <- lapply(groups, function(rows) {
    if (length(rows) == 1L) {
      return(result[rows, , drop = FALSE])
    }
    if (strategy == "highest") {
      totals <- rowSums(result[rows, expression_cols, drop = FALSE], na.rm = TRUE)
      return(result[rows[[which.max(totals)]], , drop = FALSE])
    }

    representative <- result[rows[[1L]], , drop = FALSE]
    means <- vapply(
      result[rows, expression_cols, drop = FALSE],
      mean,
      numeric(1),
      na.rm = na_action == "keep"
    )
    if (!is.null(round_digits)) {
      means <- round(means, digits = round_digits)
    }
    representative[1L, expression_cols] <- means
    representative
  })

  result <- do.call(rbind, resolved)
  rownames(result) <- NULL
  result
}

usage <- function() {
  paste(
    "Resolve duplicated gene symbols in an annotated expression matrix.",
    "",
    "Usage:",
    "  handle_gene_dups.R --input FILE [options]",
    "",
    "Options:",
    "  -i, --input FILE              Input TSV or CSV [required].",
    "  -o, --output FILE             Output TSV or CSV [default: *_deduplicated].",
    "  -s, --strategy STRATEGY       highest, mean, or suffix [default: highest].",
    "      --gene-column NAME        Duplicate key [default: gene_name].",
    "      --id-column NAME          Stable ID column [default: gene_id].",
    "      --type-column NAME        Biotype column [default: gene_type].",
    "      --expression-columns LIST Comma-separated numeric columns.",
    "      --remove-pseudogenes      Remove types containing pseudogene.",
    "      --na-action ACTION        error, drop, keep, or zero [default: error].",
    "      --round-digits N          Optionally round calculated means.",
    "      --suffix-separator TEXT   Duplicate suffix [default: _dup].",
    "  -h, --help                    Show help.",
    sep = "\n"
  )
}

parse_args <- function(args) {
  result <- list(
    input = NULL, output = NULL, strategy = "highest",
    gene_column = "gene_name", id_column = "gene_id",
    type_column = "gene_type", expression_columns = NULL,
    remove_pseudogenes = FALSE, na_action = "error",
    round_digits = NULL, suffix_separator = "_dup", help = FALSE
  )
  values <- c(
    "-i" = "input", "--input" = "input",
    "-o" = "output", "--output" = "output",
    "-s" = "strategy", "--strategy" = "strategy",
    "--gene-column" = "gene_column", "--id-column" = "id_column",
    "--type-column" = "type_column",
    "--expression-columns" = "expression_columns",
    "--na-action" = "na_action", "--round-digits" = "round_digits",
    "--suffix-separator" = "suffix_separator"
  )

  index <- 1L
  while (index <= length(args)) {
    argument <- args[[index]]
    if (argument %in% names(values)) {
      if (index == length(args)) {
        stop(sprintf("Missing value after %s.", argument), call. = FALSE)
      }
      result[[values[[argument]]]] <- args[[index + 1L]]
      index <- index + 2L
    } else if (argument == "--remove-pseudogenes") {
      result$remove_pseudogenes <- TRUE
      index <- index + 1L
    } else if (argument %in% c("-h", "--help")) {
      result$help <- TRUE
      index <- index + 1L
    } else {
      stop(sprintf("Unknown argument: %s", argument), call. = FALSE)
    }
  }

  if (result$help) return(result)
  if (is.null(result$input)) stop("--input is required.", call. = FALSE)
  if (!result$strategy %in% c("mean", "highest", "suffix")) {
    stop("--strategy must be mean, highest, or suffix.", call. = FALSE)
  }
  if (!result$na_action %in% c("error", "drop", "keep", "zero")) {
    stop("--na-action must be error, drop, keep, or zero.", call. = FALSE)
  }
  if (!is.null(result$round_digits)) {
    result$round_digits <- suppressWarnings(as.integer(result$round_digits))
    if (is.na(result$round_digits) || result$round_digits < 0L) {
      stop("--round-digits must be a non-negative integer.", call. = FALSE)
    }
  }
  result
}

read_expression <- function(path) {
  separator <- if (grepl("\\.csv$", path, ignore.case = TRUE)) "," else "\t"
  utils::read.table(
    path,
    header = TRUE,
    sep = separator,
    quote = "\"",
    comment.char = "",
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
}

write_expression <- function(data, path) {
  separator <- if (grepl("\\.csv$", path, ignore.case = TRUE)) "," else "\t"
  utils::write.table(
    data,
    path,
    sep = separator,
    quote = FALSE,
    row.names = FALSE,
    col.names = TRUE
  )
}

default_output <- function(path) {
  extension <- if (grepl("\\.csv$", path, ignore.case = TRUE)) ".csv" else ".tsv"
  stem <- sub("\\.(csv|tsv|txt)$", "", path, ignore.case = TRUE)
  paste0(stem, "_deduplicated", extension)
}

main <- function(args = commandArgs(trailingOnly = TRUE)) {
  parsed <- parse_args(args)
  if (parsed$help) {
    cat(usage(), "\n")
    return(0L)
  }
  input <- normalizePath(parsed$input, mustWork = TRUE)
  output <- parsed$output %||% default_output(input)
  expression_cols <- if (is.null(parsed$expression_columns)) {
    NULL
  } else {
    trimws(strsplit(parsed$expression_columns, ",", fixed = TRUE)[[1L]])
  }
  data <- read_expression(input)
  result <- handle_gene_duplicates(
    data,
    gene_col = parsed$gene_column,
    strategy = parsed$strategy,
    expression_cols = expression_cols,
    id_col = parsed$id_column,
    type_col = parsed$type_column,
    remove_pseudogenes = parsed$remove_pseudogenes,
    na_action = parsed$na_action,
    round_digits = parsed$round_digits,
    suffix_sep = parsed$suffix_separator
  )
  write_expression(result, output)
  message(
    "Resolved ", nrow(data) - nrow(result), " row(s) with strategy '",
    parsed$strategy, "'; wrote ", output
  )
  0L
}

if (sys.nframe() == 0L) {
  status <- tryCatch(main(), error = function(error) {
    message("[handleGeneDups] ERROR: ", conditionMessage(error))
    1L
  })
  quit(status = status)
}
