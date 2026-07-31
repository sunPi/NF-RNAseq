#!/usr/bin/env Rscript

fail <- function(...) { message("[sarsig] ERROR: ", paste0(..., collapse = "")); quit(status = 1) }
values <- commandArgs(trailingOnly = TRUE); args <- list()
while (length(values)) {
    if (length(values) < 2L || !startsWith(values[[1L]], "--")) fail("Invalid arguments")
    args[[sub("^--", "", values[[1L]])]] <- values[[2L]]
    values <- values[-c(1L, 2L)]
}
required <- c("expression", "samples-file", "signature", "signature-sha256", "output-dir")
missing <- required[!required %in% names(args)]
if (length(missing)) fail("Missing arguments: ", paste(missing, collapse = ", "))

expression <- read.delim(args$expression, check.names = FALSE, stringsAsFactors = FALSE)
samples <- trimws(readLines(args[["samples-file"]], warn = FALSE)); samples <- samples[nzchar(samples)]
if (length(samples) < 2L || anyDuplicated(samples)) fail("SarSig requires at least two unique samples")
missing_samples <- setdiff(samples, names(expression))
if (length(missing_samples)) fail("Expression is missing samples: ", paste(missing_samples, collapse = ", "))
if (!"gene_name" %in% names(expression) || anyDuplicated(expression$gene_name))
    fail("Expression must contain unique gene_name values")
signature <- trimws(readLines(args$signature, warn = FALSE)); signature <- signature[nzchar(signature)]
if (!length(signature) || anyDuplicated(signature)) fail("Invalid SarSig signature")
present <- signature[signature %in% expression$gene_name]
missing_genes <- setdiff(signature, present)
if (!length(present)) fail("No SarSig genes occur in the expression matrix")

selected <- expression[match(present, expression$gene_name), samples, drop = FALSE]
mat <- as.matrix(selected); storage.mode(mat) <- "numeric"; rownames(mat) <- present
mat <- log2(mat + 1)
scaled <- t(scale(t(mat)))
constant <- !is.finite(rowSums(scaled))
scaled[!is.finite(scaled)] <- 0
scores <- colSums(scaled)

result <- data.frame(sample = samples, SarSig_Score = scores[samples], check.names = FALSE)
output_dir <- args[["output-dir"]]; dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
write.table(result, file.path(output_dir, "SarSig_scores.tsv"), sep = "\t",
            row.names = FALSE, quote = FALSE)
write.table(data.frame(gene_name = rownames(scaled), scaled, check.names = FALSE),
            file.path(output_dir, "SarSig_gene_zscores.tsv"), sep = "\t",
            row.names = FALSE, quote = FALSE)
writeLines(present, file.path(output_dir, "signature_genes_present.txt"))
writeLines(missing_genes, file.path(output_dir, "signature_genes_missing.txt"))

ordered <- result[order(result$SarSig_Score), , drop = FALSE]
ordered$sample <- factor(ordered$sample, levels = ordered$sample)
plot <- ggplot2::ggplot(ordered, ggplot2::aes(sample, SarSig_Score, fill = SarSig_Score > 0)) +
    ggplot2::geom_col() + ggplot2::coord_flip() + ggplot2::geom_hline(yintercept = 0) +
    ggplot2::scale_fill_manual(values = c(`TRUE` = "#D55E00", `FALSE` = "#0072B2"), guide = "none") +
    ggplot2::labs(x = NULL, y = "SarSig score") + ggprism::theme_prism()
ggplot2::ggsave(file.path(output_dir, "SarSig_score.png"), plot,
                width = 8, height = max(5, 0.22 * nrow(result)), dpi = 300)

if ("design" %in% names(args)) {
    design <- read.delim(args$design, check.names = FALSE, stringsAsFactors = FALSE)
    joined <- merge(design, result, by = "sample", all.x = TRUE, sort = FALSE)
    write.table(joined, file.path(output_dir, "SarSig_with_design.tsv"), sep = "\t",
                row.names = FALSE, quote = FALSE)
}
metadata <- c(
    "method\tsum of per-gene cohort z-scores", "input\tlog2(RSEM TPM+1)",
    paste0("signature\t", normalizePath(args$signature)),
    paste0("signature_sha256\t", args[["signature-sha256"]]),
    paste0("signature_genes\t", length(signature)), paste0("genes_present\t", length(present)),
    paste0("coverage_percent\t", format(100 * length(present) / length(signature), digits = 8)),
    paste0("constant_genes_scored_zero\t", sum(constant)),
    "direction\thigher scores indicate greater expression of the SarSig program",
    "normalization_scope\tall QC-included experiment samples"
)
writeLines(c("key\tvalue", metadata), file.path(output_dir, "run_metadata.tsv"))
message("[sarsig] Completed with ", length(present), "/", length(signature),
        " signature genes (", format(100 * length(present) / length(signature), digits = 4), "% coverage)")
