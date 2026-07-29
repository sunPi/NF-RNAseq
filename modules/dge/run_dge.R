#!/usr/bin/env Rscript

fail <- function(...) {
    message("[dge] ERROR: ", paste0(..., collapse = ""))
    quit(status = 1)
}

parse_args <- function(values) {
    result <- list()
    index <- 1L
    while (index <= length(values)) {
        key <- values[[index]]
        if (!startsWith(key, "--") || index == length(values)) {
            fail("Invalid command-line arguments")
        }
        result[[substring(key, 3L)]] <- values[[index + 1L]]
        index <- index + 2L
    }
    result
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
required <- c("counts", "design", "contrasts", "output-dir", "threads")
missing <- required[!required %in% names(args)]
if (length(missing)) fail("Missing arguments: ", paste(missing, collapse = ", "))
if (!requireNamespace("DGE", quietly = TRUE)) fail("Embedded R package DGE is not installed")
if (!requireNamespace("DESeq2", quietly = TRUE)) fail("R package DESeq2 is not installed")

output_dir <- args[["output-dir"]]
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(output_dir, "contrasts"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(output_dir, "QC"), recursive = TRUE, showWarnings = FALSE)

counts_table <- read.delim(
    args$counts, check.names = FALSE, stringsAsFactors = FALSE,
    quote = "", comment.char = ""
)
design <- read.delim(
    args$design, check.names = FALSE, stringsAsFactors = FALSE,
    quote = "", comment.char = ""
)
contrasts <- read.delim(
    args$contrasts, check.names = FALSE, stringsAsFactors = FALSE,
    quote = "", comment.char = ""
)

annotation_columns <- c("gene_id", "gene_name", "gene_type")
if (!all(annotation_columns %in% names(counts_table))) {
    fail("Count matrix must contain: ", paste(annotation_columns, collapse = ", "))
}
if (!"sample" %in% names(design)) fail("Design must contain a sample column")
required_contrast_columns <- c("contrast_id", "factor", "numerator", "denominator")
if (!all(required_contrast_columns %in% names(contrasts))) {
    fail("Contrast table is missing required columns")
}
if (!nrow(contrasts)) fail("Contrast table contains no contrasts")
if (anyDuplicated(counts_table$gene_id)) fail("Count matrix contains duplicate gene_id values")
if (anyDuplicated(design$sample)) fail("Design contains duplicate samples")

sample_columns <- setdiff(names(counts_table), annotation_columns)
if (!setequal(sample_columns, design$sample)) {
    fail("Count-matrix samples and design samples do not match")
}
design <- design[match(sample_columns, design$sample), , drop = FALSE]
rownames(design) <- design$sample

count_matrix <- as.matrix(counts_table[, sample_columns, drop = FALSE])
suppressWarnings(storage.mode(count_matrix) <- "numeric")
if (anyNA(count_matrix) || any(!is.finite(count_matrix))) {
    fail("Count matrix contains non-numeric or non-finite values")
}
if (any(count_matrix < 0) || any(count_matrix != round(count_matrix))) {
    fail("DESeq2 input must contain non-negative integer counts")
}
storage.mode(count_matrix) <- "integer"
rownames(count_matrix) <- counts_table$gene_id

covariates <- grep("^covariate_", names(design), value = TRUE)
unsupported_covariates <- setdiff(covariates, "covariate_batch")
if (length(unsupported_covariates)) {
    fail(
        "DGE 0.3.0 currently supports only batch adjustment; unsupported ",
        "covariate columns: ", paste(unsupported_covariates, collapse = ", ")
    )
}
if (all(c("batch", "covariate_batch") %in% names(design))) {
    fail("Design must not contain both batch and covariate_batch")
}
adjustment_covariates <- intersect(c("batch", "covariate_batch"), names(design))
model_factors <- unique(c(adjustment_covariates, contrasts$factor))
unknown_factors <- setdiff(model_factors, names(design))
if (length(unknown_factors)) {
    fail("Contrast factors absent from design: ", paste(unknown_factors, collapse = ", "))
}
for (field in model_factors) design[[field]] <- factor(design[[field]])

formula_terms <- model_factors
design_formula <- reformulate(formula_terms)
keep <- rowSums(count_matrix) >= 10L
if (sum(keep) < 2L) fail("Fewer than two genes pass the minimum total count of 10")

suppressPackageStartupMessages(library(DESeq2))
dds <- DESeqDataSetFromMatrix(
    countData = count_matrix[keep, , drop = FALSE],
    colData = design,
    design = design_formula
)
dds <- DESeq(dds, quiet = TRUE)

normalized <- counts(dds, normalized = TRUE)
normalized_table <- cbind(
    counts_table[match(rownames(normalized), counts_table$gene_id), annotation_columns],
    as.data.frame(normalized, check.names = FALSE)
)
write.table(
    normalized_table, file.path(output_dir, "normalized_counts.tsv"),
    sep = "\t", row.names = FALSE, quote = FALSE
)

transformed <- if (nrow(dds) >= 1000L) vst(dds, blind = TRUE) else rlog(dds, blind = TRUE)
transformed_matrix <- assay(transformed)
write.table(
    cbind(gene_id = rownames(transformed_matrix),
          as.data.frame(transformed_matrix, check.names = FALSE)),
    file.path(output_dir, "variance_stabilized_expression.tsv"),
    sep = "\t", row.names = FALSE, quote = FALSE
)

sample_colours <- as.integer(design[[contrasts$factor[[1L]]]])
pca <- prcomp(t(transformed_matrix))
variance <- round(100 * pca$sdev^2 / sum(pca$sdev^2), 1)
pdf(file.path(output_dir, "QC", "PCA.pdf"), width = 8, height = 6)
plot(
    pca$x[, 1], pca$x[, 2], col = sample_colours, pch = 19, cex = 1.3,
    xlab = paste0("PC1: ", variance[[1]], "%"),
    ylab = paste0("PC2: ", variance[[2]], "%"),
    main = "DGE variance-stabilized expression"
)
text(pca$x[, 1], pca$x[, 2], labels = rownames(pca$x), pos = 3, cex = 0.65)
legend(
    "topright", legend = levels(design[[contrasts$factor[[1L]]]]),
    col = seq_along(levels(design[[contrasts$factor[[1L]]]])), pch = 19, cex = 0.8
)
dev.off()

sample_distance <- as.matrix(dist(t(transformed_matrix)))
write.table(
    cbind(sample = rownames(sample_distance),
          as.data.frame(sample_distance, check.names = FALSE)),
    file.path(output_dir, "QC", "sample_distances.tsv"),
    sep = "\t", row.names = FALSE, quote = FALSE
)
pdf(file.path(output_dir, "QC", "sample_distance_heatmap.pdf"), width = 8, height = 8)
heatmap(
    sample_distance, symm = TRUE, scale = "none",
    margins = c(10, 10), main = "Sample distances"
)
dev.off()

summary_rows <- list()
annotation <- counts_table[, annotation_columns, drop = FALSE]
rownames(annotation) <- annotation$gene_id
engine_counts <- counts_table[, c("gene_id", sample_columns), drop = FALSE]

for (index in seq_len(nrow(contrasts))) {
    contrast <- contrasts[index, , drop = FALSE]
    contrast_id <- contrast$contrast_id[[1L]]
    factor_name <- contrast$factor[[1L]]
    numerator <- contrast$numerator[[1L]]
    denominator <- contrast$denominator[[1L]]
    contrast_dir <- file.path(output_dir, "contrasts", contrast_id)
    dir.create(contrast_dir, recursive = TRUE, showWarnings = FALSE)

    engine_design <- data.frame(
        sample_id = design$sample,
        condition = as.character(design[[factor_name]]),
        stringsAsFactors = FALSE
    )
    if ("batch" %in% names(design)) {
        engine_design$batch <- design$batch
    } else if ("covariate_batch" %in% names(design)) {
        engine_design$batch <- design$covariate_batch
    }
    prepared <- DGE::prepare_dge_inputs(
        counts = engine_counts,
        design = engine_design,
        reference = denominator,
        test = numerator,
        min_total_count = 10L,
        input_type = "raw_counts"
    )
    engine_result <- DGE::run_dge(
        prepared,
        adjusted_p = 0.05,
        lfc_threshold = 0,
        annotate = FALSE
    )
    result_df <- engine_result$dge
    result_df <- cbind(
        annotation[result_df$gene_id, annotation_columns, drop = FALSE],
        result_df[, c("baseMean", "log2FoldChange", "lfcSE", "stat", "pvalue", "padj"),
                  drop = FALSE]
    )
    result_df <- result_df[order(result_df$padj, na.last = TRUE), , drop = FALSE]
    significant <- result_df[!is.na(result_df$padj) & result_df$padj < 0.05, , drop = FALSE]

    write.table(
        result_df, file.path(contrast_dir, "complete_results.tsv"),
        sep = "\t", row.names = FALSE, quote = FALSE
    )
    write.table(
        significant, file.path(contrast_dir, "significant_padj_0.05.tsv"),
        sep = "\t", row.names = FALSE, quote = FALSE
    )

    contrast_normalized <- engine_result$normalized_counts
    contrast_normalized <- cbind(
        annotation[contrast_normalized$gene_id, annotation_columns, drop = FALSE],
        contrast_normalized[, setdiff(names(contrast_normalized), "gene_id"), drop = FALSE]
    )
    write.table(
        contrast_normalized, file.path(contrast_dir, "normalized_counts.tsv"),
        sep = "\t", row.names = FALSE, quote = FALSE
    )
    saveRDS(engine_result$dds, file.path(contrast_dir, "dds.rds"))

    engine_deseq_result <- DESeq2::results(
        engine_result$dds,
        contrast = c("condition", numerator, denominator),
        alpha = 0.05
    )
    pdf(file.path(contrast_dir, "MA_plot.pdf"), width = 7, height = 6)
    DESeq2::plotMA(
        engine_deseq_result, alpha = 0.05,
        main = paste(numerator, "vs", denominator)
    )
    dev.off()

    ggplot2::ggsave(
        file.path(contrast_dir, "volcano_plot.png"),
        DGE::plot_dge_volcano(engine_result),
        width = 8, height = 7, dpi = 300
    )
    engine_heatmap <- DGE::plot_dge_heatmap(engine_result)
    if (!is.null(engine_heatmap)) {
        ggplot2::ggsave(
            file.path(contrast_dir, "heatmap_top10_bottom10.png"),
            engine_heatmap, width = 9, height = 8, dpi = 300
        )
    }

    summary_rows[[index]] <- data.frame(
        contrast_id = contrast_id, factor = factor_name,
        numerator = numerator, denominator = denominator,
        tested_genes = nrow(result_df),
        significant_padj_0.05 = nrow(significant),
        stringsAsFactors = FALSE
    )
}

write.table(
    do.call(rbind, summary_rows), file.path(output_dir, "contrast_summary.tsv"),
    sep = "\t", row.names = FALSE, quote = FALSE
)
metadata <- c(
    paste0("engine\tDGE ", as.character(packageVersion("DGE"))),
    paste0("method\tDESeq2 ", as.character(packageVersion("DESeq2"))),
    paste0("qc_design_formula\t", paste(deparse(design_formula), collapse = "")),
    "contrast_design_formula\t~ batch + condition when batch is present; otherwise ~ condition",
    paste0(
        "covariates\t",
        if (length(adjustment_covariates)) {
            paste(adjustment_covariates, collapse = ",")
        } else {
            "none"
        }
    ),
    paste0("input_matrix\t", normalizePath(args$counts)),
    paste0("input_genes\t", nrow(count_matrix)),
    paste0("tested_genes\t", sum(keep)),
    "prefilter\trowSums(counts) >= 10",
    "significance\tBenjamini-Hochberg adjusted p-value < 0.05"
)
writeLines(c("key\tvalue", metadata), file.path(output_dir, "run_metadata.tsv"))
message("[dge] Completed ", nrow(contrasts), " contrast(s): ", output_dir)
