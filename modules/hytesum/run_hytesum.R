#!/usr/bin/env Rscript

fail <- function(...) { message("[hytesum] ERROR: ", paste0(..., collapse = "")); quit(status = 1) }
values <- commandArgs(trailingOnly = TRUE); args <- list()
while (length(values)) {
    if (length(values) < 2L || !startsWith(values[[1L]], "--")) fail("Invalid arguments")
    args[[sub("^--", "", values[[1L]])]] <- values[[2L]]
    values <- values[-c(1L, 2L)]
}
required <- c("expression", "samples-file", "gmt", "gmt-sha256", "collection", "output-dir")
missing <- required[!required %in% names(args)]
if (length(missing)) fail("Missing arguments: ", paste(missing, collapse = ", "))
if (!requireNamespace("ssGSVA", quietly = TRUE)) fail("Embedded ssGSVA package is not installed")

expression <- read.delim(args$expression, check.names = FALSE, stringsAsFactors = FALSE)
required_annotation <- c("gene_id", "gene_name", "gene_type")
if (!all(required_annotation %in% names(expression))) fail("Expression annotation columns are missing")
samples <- trimws(readLines(args[["samples-file"]], warn = FALSE))
samples <- samples[nzchar(samples)]
if (!length(samples) || anyDuplicated(samples)) fail("Invalid QC sample list")
missing_samples <- setdiff(samples, names(expression))
if (length(missing_samples)) fail("Expression is missing samples: ", paste(missing_samples, collapse = ", "))
if (anyDuplicated(expression$gene_name)) fail("Expression contains duplicate gene symbols")

engine_input <- expression[, c("gene_name", samples), drop = FALSE]
names(engine_input)[1L] <- "gene"
temporary_expression <- tempfile("hytesum-expression-", fileext = ".tsv")
temporary_scores <- tempfile("hytesum-scores-")
on.exit(unlink(c(temporary_expression, temporary_scores), recursive = TRUE), add = TRUE)
write.table(engine_input, temporary_expression, sep = "\t", row.names = FALSE, quote = FALSE)

message("[hytesum] Scoring the Hallmark collection for legacy-compatible normalization")
scores <- ssGSVA::run_ssgsva(
    matrix_path = temporary_expression, gmt_path = args$gmt,
    output_dir = temporary_scores, method = "ssgsea", design_path = NULL,
    verbose = FALSE
)$ssgsea

expected <- c(
    HYPOXIA = "HALLMARK_HYPOXIA",
    TGFB = "HALLMARK_TGF_BETA_SIGNALING",
    EMT = "HALLMARK_EPITHELIAL_MESENCHYMAL_TRANSITION"
)
missing_signatures <- setdiff(unname(expected), rownames(scores))
if (length(missing_signatures)) fail("Missing HyTE signatures: ", paste(missing_signatures, collapse = ", "))
components <- t(scores[unname(expected), samples, drop = FALSE])
colnames(components) <- names(expected)
raw_sum <- rowSums(components)
score_range <- range(raw_sum)
index <- if (diff(score_range) == 0) rep(0, length(raw_sum)) else
    (raw_sum - score_range[[1L]]) / diff(score_range)
threshold <- stats::median(index)

result <- data.frame(
    sample = samples, components[samples, , drop = FALSE], HyTEsum = raw_sum[samples],
    HyTEsum_Index = index[match(samples, names(raw_sum))],
    HyTEsum_Percent = 100 * index[match(samples, names(raw_sum))],
    median_group = ifelse(index[match(samples, names(raw_sum))] > threshold, "High", "Low"),
    check.names = FALSE, row.names = NULL
)
dir.create(args[["output-dir"]], recursive = TRUE, showWarnings = FALSE)
write.table(result, file.path(args[["output-dir"]], "HyTEsum_scores.tsv"),
            sep = "\t", row.names = FALSE, quote = FALSE)
writeLines(result$sample[result$median_group == "High"],
           file.path(args[["output-dir"]], "HyTEsum_high_samples.txt"))
writeLines(result$sample[result$median_group == "Low"],
           file.path(args[["output-dir"]], "HyTEsum_low_samples.txt"))

if (requireNamespace("writexl", quietly = TRUE)) {
    writexl::write_xlsx(list(
        HyTEsum = result,
        Low = result[result$median_group == "Low", , drop = FALSE],
        High = result[result$median_group == "High", , drop = FALSE]
    ), file.path(args[["output-dir"]], "HyTEsum_Index.xlsx"))
}

plot_order <- result[order(result$HyTEsum_Index), , drop = FALSE]
plot_order$sample <- factor(plot_order$sample, levels = plot_order$sample)
plot <- ggplot2::ggplot(plot_order, ggplot2::aes(sample, HyTEsum_Index, fill = median_group)) +
    ggplot2::geom_col() + ggplot2::coord_flip() +
    ggplot2::scale_fill_manual(values = c(Low = "#888888", High = "#077F97")) +
    ggplot2::labs(x = NULL, y = "HyTEsum index", fill = "Median group") +
    ggprism::theme_prism()
ggplot2::ggsave(file.path(args[["output-dir"]], "HyTEsum_index.png"), plot,
                width = 8, height = max(5, 0.22 * nrow(result)), dpi = 300)

if ("design" %in% names(args)) {
    design <- read.delim(args$design, check.names = FALSE, stringsAsFactors = FALSE)
    annotated <- merge(design, result, by = "sample", all.x = TRUE, sort = FALSE)
    write.table(annotated, file.path(args[["output-dir"]], "HyTEsum_with_design.tsv"),
                sep = "\t", row.names = FALSE, quote = FALSE)
}

metadata <- c(
    paste0("engine\tssGSVA ", as.character(packageVersion("ssGSVA"))),
    paste0("collection\t", args$collection), paste0("gmt\t", normalizePath(args$gmt)),
    paste0("gmt_sha256\t", args[["gmt-sha256"]]), "input_value\tRSEM TPM",
    "components\tHALLMARK_HYPOXIA,HALLMARK_TGF_BETA_SIGNALING,HALLMARK_EPITHELIAL_MESENCHYMAL_TRANSITION",
    "raw_score\tsum of three ssGSEA scores", "index\tcohort min-max normalization",
    paste0("median_threshold\t", format(threshold, digits = 15)),
    "median_split\tHigh is strictly above median; ties remain Low"
)
writeLines(c("key\tvalue", metadata), file.path(args[["output-dir"]], "run_metadata.tsv"))
message("[hytesum] Completed: ", args[["output-dir"]])
