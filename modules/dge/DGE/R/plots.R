LOW_COLOUR <- "#077F97"
HIGH_COLOUR <- "#400257"

#' Plot DGE volcano
#' @param result Output from `run_dge()`.
#' @return ggplot object.
#' @export
plot_dge_volcano <- function(result) {
  data <- result$dge
  data$direction <- "Not significant"
  sig <- !is.na(data$padj) & data$padj < result$adjusted_p &
    abs(data$log2FoldChange) >= result$lfc_threshold
  data$direction[sig & data$log2FoldChange < 0] <- "Low / negative"
  data$direction[sig & data$log2FoldChange >= 0] <- "High / positive"
  data$minus_log10_padj <- -log10(pmax(data$padj, .Machine$double.xmin))
  ggplot2::ggplot(data, ggplot2::aes(x = log2FoldChange,
                                     y = minus_log10_padj,
                                     colour = direction)) +
    ggplot2::geom_point(alpha = .7, size = 1.5, na.rm = TRUE) +
    ggplot2::geom_hline(yintercept = -log10(result$adjusted_p),
                        linetype = "dashed", colour = "grey40") +
    ggplot2::scale_colour_manual(values = c(
      "Low / negative" = LOW_COLOUR, "Not significant" = "grey75",
      "High / positive" = HIGH_COLOUR)) +
    ggplot2::labs(
      title = paste(result$test, "vs", result$reference),
      x = "log2 fold change", y = "-log10 adjusted P", colour = NULL) +
    ggprism::theme_prism(base_size = 12)
}

#' Plot a top/bottom DGE heatmap
#' @param result Output from `run_dge()`.
#' @param n Number selected from each fold-change extreme.
#' @return ggplot object or NULL when fewer than 10 significant genes exist.
#' @export
plot_dge_heatmap <- function(result, n = 10L) {
  sig <- result$significant
  if (nrow(sig) < 10L) return(NULL)
  ordered <- sig[order(sig$log2FoldChange), , drop = FALSE]
  selected <- unique(c(utils::head(ordered$gene_id, n),
                       utils::tail(ordered$gene_id, n)))
  matrix_data <- result$normalized_counts
  rownames(matrix_data) <- matrix_data$gene_id
  matrix_data <- as.matrix(matrix_data[selected, setdiff(names(matrix_data), "gene_id"),
                                        drop = FALSE])
  plot_matrix <- if (identical(result$method, "deseq2")) {
    log2(matrix_data + 1)
  } else {
    matrix_data
  }
  scaled <- t(scale(t(plot_matrix)))
  scaled[!is.finite(scaled)] <- 0
  labels <- selected
  if ("gene_symbol" %in% names(sig)) {
    symbols <- sig$gene_symbol[match(selected, sig$gene_id)]
    labels[!is.na(symbols) & nzchar(symbols)] <- symbols[!is.na(symbols) & nzchar(symbols)]
  }
  long <- as.data.frame(as.table(scaled), stringsAsFactors = FALSE)
  names(long) <- c("gene", "sample", "z_score")
  long$gene <- factor(long$gene, levels = rev(selected), labels = rev(labels))
  ggplot2::ggplot(long, ggplot2::aes(x = sample, y = gene, fill = z_score)) +
    ggplot2::geom_tile() +
    ggplot2::scale_fill_gradient2(low = LOW_COLOUR, mid = "white",
                                  high = HIGH_COLOUR, midpoint = 0,
                                  name = "Row z-score") +
    ggplot2::labs(title = "Top and bottom significant genes",
                  x = NULL, y = NULL) +
    ggprism::theme_prism(base_size = 10) +
    ggplot2::theme(axis.text.x = ggplot2::element_text(
      angle = 90, hjust = 1, vjust = .5))
}
