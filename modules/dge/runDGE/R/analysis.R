annotate_ensembl <- function(results) {
  ids <- sub("\\..*$", "", results$gene_id)
  is_ensembl <- grepl("^ENSG[0-9]+$", ids)
  results$gene_symbol <- NA_character_
  if (any(is_ensembl) && requireNamespace("org.Hs.eg.db", quietly = TRUE) &&
      requireNamespace("AnnotationDbi", quietly = TRUE)) {
    results$gene_symbol[is_ensembl] <- unname(AnnotationDbi::mapIds(
      org.Hs.eg.db::org.Hs.eg.db, keys = ids[is_ensembl],
      keytype = "ENSEMBL", column = "SYMBOL", multiVals = "first"))
  }
  results
}

#' Run an explicit DESeq2 contrast
#' @param prepared Output from `prepare_dge_inputs()`.
#' @param adjusted_p Adjusted-P significance threshold.
#' @param lfc_threshold Absolute log2-fold-change threshold.
#' @param annotate Add human symbols for recognizable ENSEMBL identifiers.
#' @return DGE analysis object.
#' @export
run_dge <- function(prepared, adjusted_p = 0.05, lfc_threshold = 0,
                    annotate = TRUE) {
  if (!is.numeric(adjusted_p) || length(adjusted_p) != 1L ||
      adjusted_p <= 0 || adjusted_p > 1)
    stop("adjusted_p must be greater than zero and at most one")
  model_formula <- if ("batch" %in% names(prepared$design)) {
    stats::as.formula("~ batch + condition")
  } else {
    stats::as.formula("~ condition")
  }
  model_matrix <- stats::model.matrix(model_formula, data = prepared$design)
  if (qr(model_matrix)$rank < ncol(model_matrix))
    stop("The design is not full rank; batch and condition may be confounded")
  dds <- DESeq2::DESeqDataSetFromMatrix(
    countData = prepared$counts, colData = prepared$design,
    design = model_formula)
  dds <- DESeq2::estimateSizeFactors(dds)
  dds <- DESeq2::estimateDispersionsGeneEst(dds, quiet = TRUE)
  fitted <- tryCatch(
    DESeq2::estimateDispersionsFit(dds, quiet = TRUE),
    error = function(error) error)
  if (inherits(fitted, "error")) {
    if (!grepl("all gene-wise dispersion estimates", conditionMessage(fitted),
               fixed = TRUE)) stop(fitted)
    message("Using gene-wise dispersion estimates for this small/low-variance dataset")
    SummarizedExperiment::mcols(dds)$dispersion <-
      SummarizedExperiment::mcols(dds)$dispGeneEst
  } else {
    dds <- DESeq2::estimateDispersionsMAP(fitted, quiet = TRUE)
  }
  dds <- DESeq2::nbinomWaldTest(dds, quiet = TRUE)
  contrast <- c("condition", prepared$test, prepared$reference)
  table <- as.data.frame(DESeq2::results(
    dds, contrast = contrast, alpha = adjusted_p))
  table <- data.frame(gene_id = rownames(table), table, row.names = NULL,
                      check.names = FALSE)
  if (annotate) table <- annotate_ensembl(table)
  table <- table[order(table$padj, -abs(table$log2FoldChange), na.last = TRUE), ]
  significant <- table[!is.na(table$padj) & table$padj < adjusted_p &
                         abs(table$log2FoldChange) >= lfc_threshold, ]
  normalized <- as.data.frame(DESeq2::counts(dds, normalized = TRUE),
                              check.names = FALSE)
  normalized <- data.frame(gene_id = rownames(normalized), normalized,
                           row.names = NULL, check.names = FALSE)
  list(dds = dds, dge = table, significant = significant,
       normalized_counts = normalized, counts = prepared$counts,
       design = prepared$design, reference = prepared$reference,
       test = prepared$test, adjusted_p = adjusted_p,
       lfc_threshold = lfc_threshold, method = "deseq2", model = dds,
       batch_adjusted = "batch" %in% names(prepared$design))
}

#' Run limma differential-expression analysis
#' @param prepared Output from `prepare_dge_inputs()`.
#' @param adjusted_p Adjusted-P significance threshold.
#' @param lfc_threshold Absolute log2-fold-change threshold.
#' @param annotate Add human symbols for recognizable ENSEMBL identifiers.
#' @return DGE analysis object with the same result schema as `run_dge()`.
#' @export
run_limma_dge <- function(
    prepared, adjusted_p = 0.05,
    lfc_threshold = 1, annotate = TRUE) {
  if (prepared$input_type != "normalized")
    stop("limma-trend requires normalized continuous expression")
  condition <- prepared$design$condition
  design_formula <- if ("batch" %in% names(prepared$design)) {
    stats::as.formula("~ 0 + condition + batch")
  } else {
    stats::as.formula("~ 0 + condition")
  }
  design <- stats::model.matrix(design_formula, data = prepared$design)
  colnames(design) <- make.names(colnames(design))
  if (qr(design)$rank < ncol(design))
    stop("The design is not full rank; batch and condition may be confounded")
  contrast_text <- paste0(
    make.names(paste0("condition", prepared$test)), "-",
    make.names(paste0("condition", prepared$reference)))
  contrast <- limma::makeContrasts(contrasts = contrast_text, levels = design)
  expression <- prepared$counts
  transformation <- "none"
  if (all(expression >= 0)) {
    expression <- log2(expression + 1)
    transformation <- "log2(x + 1)"
  }
  fit <- limma::lmFit(expression, design)
  normalized_matrix <- expression
  fit <- limma::contrasts.fit(fit, contrast)
  fit <- limma::eBayes(fit, trend = TRUE, robust = TRUE)
  table <- limma::topTable(fit, number = Inf, sort.by = "none",
                           adjust.method = "BH")
  table <- data.frame(
    gene_id = rownames(table), baseMean = rowMeans(normalized_matrix),
    log2FoldChange = table$logFC, lfcSE = NA_real_, stat = table$t,
    pvalue = table$P.Value, padj = table$adj.P.Val,
    row.names = NULL, check.names = FALSE)
  if (annotate) table <- annotate_ensembl(table)
  table <- table[order(table$padj, -abs(table$log2FoldChange), na.last = TRUE), ]
  significant <- table[!is.na(table$padj) & table$padj < adjusted_p &
                         abs(table$log2FoldChange) >= lfc_threshold, ]
  normalized <- data.frame(
    gene_id = rownames(normalized_matrix), as.data.frame(normalized_matrix),
    row.names = NULL, check.names = FALSE)
  list(dge = table, significant = significant,
       normalized_counts = normalized, counts = prepared$counts,
       design = prepared$design, reference = prepared$reference,
       test = prepared$test, adjusted_p = adjusted_p,
       lfc_threshold = lfc_threshold, method = "limma-trend", model = fit,
       transformation = transformation,
       batch_adjusted = "batch" %in% names(prepared$design))
}
