test_that("DESeq2 analysis has explicit outputs", {
  set.seed(7)
  counts <- matrix(rnbinom(120 * 6, mu = 100, size = 10), nrow = 120)
  counts[1:20, 4:6] <- counts[1:20, 4:6] * 5L
  input <- data.frame(gene_id = paste0("gene", seq_len(120)), counts,
                      check.names = FALSE)
  names(input)[-1] <- c("C1", "C2", "C3", "T1", "T2", "T3")
  design <- data.frame(
    sample_id = names(input)[-1],
    condition = rep(c("Control", "Treatment"), each = 3))
  prepared <- prepare_dge_inputs(input, design, reference = "Control")
  result <- run_dge(prepared, adjusted_p = 0.1, annotate = FALSE)
  expect_true(all(c("gene_id", "log2FoldChange", "padj") %in% names(result$dge)))
  expect_equal(colnames(result$counts), design$sample_id)
  expect_s3_class(plot_dge_volcano(result), "ggplot")
})

test_that("limma-trend analyzes normalized continuous expression", {
  set.seed(11)
  matrix_data <- matrix(rnorm(100 * 8, -1, .5), nrow = 100)
  matrix_data[1:15, 5:8] <- matrix_data[1:15, 5:8] + 2
  input <- data.frame(gene_id = paste0("gene", seq_len(100)), matrix_data,
                      check.names = FALSE)
  names(input)[-1] <- paste0(rep(c("C", "T"), each = 4), 1:4)
  design <- data.frame(sample_id = names(input)[-1],
                       condition = rep(c("Control", "Treatment"), each = 4))
  prepared <- prepare_dge_inputs(
    input, design, reference = "Control", input_type = "normalized")
  result <- run_limma_dge(
    prepared, adjusted_p = 0.1, annotate = FALSE)
  expect_equal(result$method, "limma-trend")
  expect_true(nrow(result$significant) >= 10)
  expect_s3_class(plot_dge_heatmap(result), "ggplot")
})

test_that("batch is included in DESeq2 and limma models", {
  set.seed(23)
  matrix_data <- matrix(rnbinom(100 * 8, mu = 80, size = 8), nrow = 100)
  input <- data.frame(gene_id = paste0("gene", seq_len(100)), matrix_data,
                      check.names = FALSE)
  names(input)[-1] <- paste0(rep(c("C", "T"), each = 4), 1:4)
  design <- data.frame(
    sample_id = names(input)[-1],
    condition = rep(c("Control", "Treatment"), each = 4),
    batch = rep(c("B1", "B2"), 4))
  raw <- prepare_dge_inputs(input, design, reference = "Control")
  expect_true(run_dge(raw, annotate = FALSE)$batch_adjusted)
  normalized_input <- input
  normalized_input[-1] <- log2(normalized_input[-1] + 1)
  normalized <- prepare_dge_inputs(
    normalized_input, design, reference = "Control",
    input_type = "normalized")
  expect_true(run_limma_dge(normalized, annotate = FALSE)$batch_adjusted)
})
