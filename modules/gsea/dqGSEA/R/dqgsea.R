utils::globalVariables(c("pathway", "NES", "Direction"))

#' Read a differential-expression results table
#'
#' @param path Path to a CSV or tab-delimited file.
#' @return A data frame.
#' @export
read_dge <- function(path) {
  if (!file.exists(path)) stop("DGE table not found: ", path, call. = FALSE)
  extension <- tolower(tools::file_ext(path))
  data <- if (extension == "csv") {
    utils::read.csv(path, check.names = FALSE)
  } else {
    utils::read.delim(path, check.names = FALSE)
  }
  if (nrow(data) == 0L) stop("DGE table contains no rows.", call. = FALSE)
  data
}

#' Prepare a named, ranked gene vector
#'
#' Duplicate gene identifiers are collapsed using their mean rank statistic.
#'
#' @param dge Differential-expression results data frame.
#' @param gene_column Gene identifier column. When NULL, gene_symbol is
#'   preferred over gene_id.
#' @param rank_column Numeric ranking column. Defaults to stat.
#' @return A decreasing named numeric vector.
#' @export
prepare_gene_ranks <- function(dge, gene_column = NULL, rank_column = "stat") {
  if (is.null(gene_column)) {
    candidates <- c("gene_symbol", "gene_id")
    gene_column <- candidates[candidates %in% names(dge)][1L]
  }
  if (length(gene_column) == 0L || is.na(gene_column)) {
    stop("No gene identifier column found. Add gene_symbol/gene_id or use --gene-column.", call. = FALSE)
  }
  if (!gene_column %in% names(dge)) stop("Gene column not found: ", gene_column, call. = FALSE)
  if (!rank_column %in% names(dge)) stop("Rank column not found: ", rank_column, call. = FALSE)

  gene <- trimws(as.character(dge[[gene_column]]))
  statistic <- suppressWarnings(as.numeric(dge[[rank_column]]))
  keep <- !is.na(gene) & nzchar(gene) & is.finite(statistic)
  gene <- gene[keep]
  statistic <- statistic[keep]
  if (length(statistic) == 0L) {
    stop("No usable gene ranks remain after removing missing values.", call. = FALSE)
  }

  collapsed <- stats::aggregate(statistic, by = list(gene = gene), FUN = mean)
  ranks <- collapsed$x
  names(ranks) <- collapsed$gene
  ranks <- sort(ranks, decreasing = TRUE)

  # Preserve the deterministic tie-breaking used by the legacy dqGSEA
  # workflow without materially changing the ranking statistic.
  offsets <- (as.integer(factor(names(ranks))) %% 1000L) * 1e-12
  sort(ranks + offsets, decreasing = TRUE)
}

plot_gsea <- function(results, output_path, title = NULL) {
  significant <- results[!is.na(results$padj), , drop = FALSE]
  if (nrow(significant) == 0L) return(invisible(NULL))
  significant <- significant[order(significant$NES, decreasing = TRUE), , drop = FALSE]
  base_size <- if (nrow(significant) > 35L) 5 else 10
  significant$Direction <- ifelse(
    significant$NES > 0, "Upregulated", "Downregulated"
  )

  plot <- ggplot2::ggplot(
    significant,
    ggplot2::aes(x = stats::reorder(pathway, NES), y = NES)
  ) +
    ggplot2::geom_col(ggplot2::aes(fill = Direction)) +
    ggplot2::coord_flip() +
    ggplot2::labs(
      x = "Pathway", y = "Normalized Enrichment Score", title = title
    ) +
    ggplot2::theme(
      text = ggplot2::element_text(size = 8),
      title = ggplot2::element_text(size = 18),
      plot.title = ggplot2::element_text(hjust = 0.5)
    ) +
    ggplot2::scale_fill_manual(values = c(
      Upregulated = "#077f97", Downregulated = "#400257"
    )) +
    ggprism::theme_prism(base_size = base_size)

  ggplot2::ggsave(output_path, plot, width = 3200 / 300,
                  height = 1800 / 300, dpi = 300)
  invisible(plot)
}

#' Run preranked gene set enrichment analysis
#'
#' @param dge_path DGE results table containing gene identifiers and a rank statistic.
#' @param gmt_path GMT pathway file.
#' @param output_dir Output directory.
#' @param padj_threshold Adjusted p-value threshold.
#' @param gene_column Optional gene identifier column.
#' @param rank_column Ranking column.
#' @param min_size Minimum pathway size.
#' @param max_size Maximum pathway size.
#' @return The complete fgsea results invisibly.
#' @export
run_dqgsea <- function(dge_path, gmt_path, output_dir = "results",
                       padj_threshold = 0.05, gene_column = NULL,
                       rank_column = "stat", min_size = 10L, max_size = 500L,
                       title = NULL) {
  if (!file.exists(gmt_path)) stop("GMT file not found: ", gmt_path, call. = FALSE)
  if (!is.numeric(padj_threshold) || length(padj_threshold) != 1L ||
      is.na(padj_threshold) || padj_threshold < 0 || padj_threshold > 1) {
    stop("--padj must be a number between 0 and 1.", call. = FALSE)
  }

  dge <- read_dge(dge_path)
  ranks <- prepare_gene_ranks(dge, gene_column, rank_column)
  pathways <- fgsea::gmtPathways(gmt_path)
  if (length(pathways) == 0L) stop("GMT file contains no pathways.", call. = FALSE)
  overlap <- intersect(names(ranks), unique(unlist(pathways, use.names = FALSE)))
  if (length(overlap) == 0L) {
    stop("No gene identifiers overlap between the DGE table and GMT file. Check --gene-column and identifier type.", call. = FALSE)
  }

  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(
    data.frame(gene = names(ranks), rank = unname(ranks)),
    file.path(output_dir, "gene_ranks.csv"),
    row.names = FALSE
  )

  set.seed(1L)
  result <- fgsea::fgseaMultilevel(
    pathways = pathways, stats = ranks,
    minSize = as.integer(min_size), maxSize = as.integer(max_size),
    BPPARAM = BiocParallel::SerialParam(progressbar = FALSE)
  )
  result <- as.data.frame(result)
  result <- result[order(result$padj, -abs(result$NES), na.last = TRUE), , drop = FALSE]
  if ("leadingEdge" %in% names(result)) {
    result$leadingEdge <- vapply(result$leadingEdge, paste, collapse = ";", FUN.VALUE = character(1))
  }
  significant <- result[!is.na(result$padj) & result$padj <= padj_threshold, , drop = FALSE]
  utils::write.csv(result, file.path(output_dir, "gsea.csv"), row.names = FALSE)
  utils::write.csv(significant, file.path(output_dir, "gsea_significant.csv"), row.names = FALSE)

  if (nrow(significant) > 0L) {
    plot_gsea(significant, file.path(output_dir, "gsea_plot.png"), title = title)
  } else {
    message("No pathways passed the adjusted p-value threshold; plot skipped.")
  }
  message("Analysed ", length(ranks), " genes across ", length(pathways),
          " pathways; ", nrow(significant), " significant.")
  invisible(result)
}
