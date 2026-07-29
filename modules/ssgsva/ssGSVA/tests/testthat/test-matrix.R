test_that("expression matrices are numeric", {
  path <- tempfile(fileext = ".csv")
  utils::write.csv(
    data.frame(
      gene_id = c("A", "B"),
      S1 = c(1, 5),
      S2 = c(2, 6)
    ),
    path,
    row.names = FALSE
  )
  matrix <- prepare_expression_matrix(path)
  expect_equal(rownames(matrix), c("A", "B"))
  expect_equal(unname(matrix["A", ]), c(1, 2))
})

test_that("duplicate genes are delegated to handleGeneDups", {
  path <- tempfile(fileext = ".csv")
  utils::write.csv(
    data.frame(gene_id = c("A", "A"), S1 = c(1, 3)),
    path,
    row.names = FALSE
  )
  expect_error(prepare_expression_matrix(path), "Run handleGeneDups")
})

test_that("nonnumeric expression values fail clearly", {
  path <- tempfile(fileext = ".csv")
  utils::write.csv(
    data.frame(gene_id = "A", S1 = "not-a-number"),
    path,
    row.names = FALSE
  )
  expect_error(prepare_expression_matrix(path), "only numeric")
})
