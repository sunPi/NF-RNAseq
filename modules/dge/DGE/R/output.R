#' Write stable DGE outputs
#' @param result Output from `run_dge()`.
#' @param output Output directory.
#' @return Named paths.
#' @export
write_dge_results <- function(result, output = "results") {
  dir.create(output, recursive = TRUE, showWarnings = FALSE)
  paths <- c(
    dge = file.path(output, "dge.csv"),
    significant = file.path(output, "dge_significant.csv"),
    volcano = file.path(output, "volcano_plot.png"))
  model_name <- if (identical(result$method, "deseq2")) "dds.rds" else
    "limma_fit.rds"
  paths <- c(paths, model = file.path(output, model_name))
  utils::write.csv(result$dge, paths[["dge"]], row.names = FALSE, na = "")
  utils::write.csv(result$significant, paths[["significant"]],
                   row.names = FALSE, na = "")
  saveRDS(result$model, paths[["model"]])
  ggplot2::ggsave(paths[["volcano"]], plot_dge_volcano(result),
                  width = 8, height = 7, dpi = 300)
  heatmap <- plot_dge_heatmap(result)
  if (!is.null(heatmap)) {
    paths <- c(paths, heatmap = file.path(
      output, "heatmap_top10_bottom10.png"))
    ggplot2::ggsave(paths[["heatmap"]], heatmap, width = 9, height = 8,
                    dpi = 300)
  } else {
    message("Skipping heatmap: fewer than 10 significant genes")
  }
  invisible(paths)
}
