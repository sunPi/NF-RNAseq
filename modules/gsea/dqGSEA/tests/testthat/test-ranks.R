test_that("gene ranks are filtered, collapsed, and sorted", {
  dge <- data.frame(
    gene_id = c("A", "B", "A", "", "C"),
    stat = c(2, -1, 4, 8, NA)
  )
  ranks <- prepare_gene_ranks(dge)
  expect_equal(unname(ranks), c(3, -1))
  expect_equal(names(ranks), c("A", "B"))
})

test_that("gene_symbol is preferred automatically", {
  dge <- data.frame(
    gene_id = c("ENSG1", "ENSG2"),
    gene_symbol = c("TP53", "EGFR"),
    stat = c(1, 2)
  )
  expect_equal(names(prepare_gene_ranks(dge)), c("EGFR", "TP53"))
})

test_that("missing required columns produce clear errors", {
  expect_error(prepare_gene_ranks(data.frame(value = 1)), "No gene identifier column")
  expect_error(prepare_gene_ranks(data.frame(gene_id = "A")), "Rank column not found")
})
