test_that("workflow writes complete and significant results", {
  skip_if_not_installed("fgsea")
  directory <- tempfile("dqgsea-")
  dir.create(directory)
  dge_path <- file.path(directory, "dge.csv")
  gmt_path <- file.path(directory, "pathways.gmt")
  output_path <- file.path(directory, "results")
  set.seed(1)
  genes <- paste0("G", seq_len(100))
  utils::write.csv(
    data.frame(gene_id = genes, stat = stats::rnorm(100)),
    dge_path,
    row.names = FALSE
  )
  writeLines(c(
    paste(c("PATHWAY_A", "test", genes[1:30]), collapse = "\t"),
    paste(c("PATHWAY_B", "test", genes[31:60]), collapse = "\t")
  ), gmt_path)
  expect_message(
    run_dqgsea(dge_path, gmt_path, output_path, min_size = 5, max_size = 100),
    "Analysed 100 genes"
  )
  expect_true(file.exists(file.path(output_path, "gene_ranks.csv")))
  expect_true(file.exists(file.path(output_path, "gsea.csv")))
  expect_true(file.exists(file.path(output_path, "gsea_significant.csv")))
})
