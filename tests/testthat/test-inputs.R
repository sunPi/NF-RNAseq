test_that("samples are aligned to count columns", {
  counts <- data.frame(gene_id = c("g1", "g2"), S2 = c(2, 5), S1 = c(3, 6))
  design <- data.frame(sample_id = c("S1", "S2"),
                       condition = c("control", "treated"))
  x <- prepare_dge_inputs(counts, design, reference = "control",
                          min_total_count = 0)
  expect_equal(rownames(x$design), c("S2", "S1"))
  expect_equal(x$test, "treated")
})

test_that("unsafe inputs fail clearly", {
  design <- data.frame(sample_id = c("S1", "S2"),
                       condition = c("control", "treated"))
  expect_error(prepare_dge_inputs(
    data.frame(gene_id = "g1", S1 = 1.2, S2 = 2), design,
    reference = "control", min_total_count = 0), "raw integer counts")
  expect_error(prepare_dge_inputs(
    data.frame(gene_id = "g1", S1 = 1, S3 = 2), design,
    reference = "control", min_total_count = 0), "sample mismatch")
})

test_that("normalized matrices accept continuous and negative log values", {
  counts <- data.frame(gene_id = c("g1", "g2"),
                       S1 = c(-2.1, 4.2), S2 = c(-1.8, 5.1))
  design <- data.frame(sample_id = c("S1", "S2"),
                       condition = c("control", "treated"))
  x <- prepare_dge_inputs(counts, design, reference = "control",
                          min_total_count = 0, input_type = "normalized")
  expect_type(x$counts, "double")
})

test_that("invalid batch columns fail", {
  counts <- data.frame(gene_id = c("g1", "g2"),
                       S1 = c(2, 4), S2 = c(3, 5))
  design <- data.frame(sample_id = c("S1", "S2"),
                       condition = c("control", "treated"),
                       batch = c("B1", "B1"))
  expect_error(prepare_dge_inputs(
    counts, design, reference = "control", min_total_count = 0),
    "at least two batch levels")
})
