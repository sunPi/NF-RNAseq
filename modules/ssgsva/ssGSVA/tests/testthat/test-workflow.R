test_that("ssGSEA workflow writes compatible outputs", {
  skip_if_not_installed("GSVA")
  directory <- tempfile("ssgsva-")
  dir.create(directory)
  matrix_path <- file.path(directory, "expression.csv")
  gmt_path <- file.path(directory, "collection.gmt")
  output_path <- file.path(directory, "results")

  set.seed(1)
  genes <- paste0("G", seq_len(100))
  expression <- data.frame(
    gene_id = genes,
    S1 = stats::rnorm(100),
    S2 = stats::rnorm(100),
    S3 = stats::rnorm(100)
  )
  utils::write.csv(expression, matrix_path, row.names = FALSE)
  writeLines(c(
    paste(c("SET_A", "test", genes[1:30]), collapse = "\t"),
    paste(c("SET_B", "test", genes[31:60]), collapse = "\t")
  ), gmt_path)

  expect_message(
    run_ssgsva(matrix_path, gmt_path, output_path, method = "ssgsea"),
    "Completed ssgsea"
  )
  expect_true(file.exists(
    file.path(output_path, "ssgsea", "collection_ssGSEA.csv")
  ))
  expect_true(file.exists(
    file.path(output_path, "ssgsea", "collection_ssGSEA.RDS")
  ))
  expect_true(file.exists(
    file.path(output_path, "ssgsea", "collection_ssGSEA_plot.png")
  ))
})
