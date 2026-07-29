#!/usr/bin/env Rscript

fail <- function(...) {
    message("[ssgsva] ERROR: ", paste0(..., collapse = ""))
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
required <- c(
    "expression", "samples-file", "gmt", "collection", "gmt-sha256",
    "method", "output-dir"
)
missing <- required[!required %in% names(args)]
if (length(missing)) fail("Missing arguments: ", paste(missing, collapse = ", "))
if (!requireNamespace("ssGSVA", quietly = TRUE)) {
    fail("Embedded R package ssGSVA is not installed")
}
if (!requireNamespace("limma", quietly = TRUE)) fail("R package limma is not installed")

expression <- read.delim(
    args$expression, check.names = FALSE, stringsAsFactors = FALSE,
    quote = "", comment.char = ""
)
annotation_columns <- c("gene_id", "gene_name", "gene_type")
if (!all(annotation_columns %in% names(expression))) {
    fail("Expression matrix is missing gene_id, gene_name, or gene_type")
}
samples <- trimws(readLines(args[["samples-file"]], warn = FALSE))
samples <- samples[nzchar(samples)]
if (!length(samples) || anyDuplicated(samples)) fail("Invalid QC sample list")
missing_samples <- setdiff(samples, names(expression))
if (length(missing_samples)) {
    fail("Expression matrix is missing samples: ", paste(missing_samples, collapse = ", "))
}
if (anyNA(expression$gene_name) || any(!nzchar(trimws(expression$gene_name)))) {
    fail("Deduplicated expression matrix contains empty gene_name values")
}
if (anyDuplicated(expression$gene_name)) {
    fail("Deduplicated expression matrix still contains duplicate gene_name values")
}

engine_input <- expression[, c("gene_name", samples), drop = FALSE]
names(engine_input)[[1L]] <- "gene"
temporary_expression <- tempfile("ssgsva-expression-", fileext = ".tsv")
write.table(
    engine_input, temporary_expression, sep = "\t",
    row.names = FALSE, quote = FALSE
)
on.exit(unlink(temporary_expression), add = TRUE)

design_path <- if ("design" %in% names(args)) args$design else NULL
scores <- ssGSVA::run_ssgsva(
    matrix_path = temporary_expression,
    gmt_path = args$gmt,
    output_dir = args[["output-dir"]],
    method = args$method,
    design_path = design_path,
    verbose = FALSE
)

unlink(file.path(args[["output-dir"]], "differential"), recursive = TRUE)
unlink(file.path(args[["output-dir"]], "differential_summary.tsv"))

for (method_name in names(scores)) {
    score_table <- data.frame(
        pathway = rownames(scores[[method_name]]),
        as.data.frame(scores[[method_name]], check.names = FALSE),
        row.names = NULL,
        check.names = FALSE
    )
    write.table(
        score_table,
        file.path(args[["output-dir"]], method_name, "scores.tsv"),
        sep = "\t", row.names = FALSE, quote = FALSE
    )
}

contrast_summaries <- list()
if ("design" %in% names(args) && "contrasts" %in% names(args)) {
    design <- read.delim(
        args$design, check.names = FALSE, stringsAsFactors = FALSE,
        quote = "", comment.char = ""
    )
    contrasts <- read.delim(
        args$contrasts, check.names = FALSE, stringsAsFactors = FALSE,
        quote = "", comment.char = ""
    )
    design <- design[match(samples, design$sample), , drop = FALSE]
    if (anyNA(design$sample)) fail("Validated design and score samples do not match")
    batch_column <- intersect(c("batch", "covariate_batch"), names(design))
    if (length(batch_column) > 1L) fail("Design must not contain both batch and covariate_batch")

    for (method_name in names(scores)) {
        method_scores <- scores[[method_name]]
        for (contrast_index in seq_len(nrow(contrasts))) {
            contrast <- contrasts[contrast_index, , drop = FALSE]
            factor_name <- contrast$factor[[1L]]
            numerator <- contrast$numerator[[1L]]
            denominator <- contrast$denominator[[1L]]
            contrast_id <- contrast$contrast_id[[1L]]
            keep <- design[[factor_name]] %in% c(numerator, denominator)
            contrast_design <- design[keep, , drop = FALSE]
            contrast_scores <- method_scores[, contrast_design$sample, drop = FALSE]
            group <- relevel(factor(contrast_design[[factor_name]]), ref = denominator)

            if (length(batch_column)) {
                batch <- factor(contrast_design[[batch_column]])
                if (nlevels(batch) < 2L) {
                    fail("Batch adjustment requires at least two levels in ", contrast_id)
                }
                model <- model.matrix(~ 0 + group + batch)
            } else {
                model <- model.matrix(~ 0 + group)
            }
            colnames(model) <- make.names(colnames(model))
            if (qr(model)$rank < ncol(model)) {
                fail("Differential score design is not full rank for ", contrast_id)
            }
            numerator_column <- make.names(paste0("group", numerator))
            denominator_column <- make.names(paste0("group", denominator))
            contrast_vector <- rep(0, ncol(model))
            names(contrast_vector) <- colnames(model)
            contrast_vector[[numerator_column]] <- 1
            contrast_vector[[denominator_column]] <- -1

            fit <- limma::lmFit(contrast_scores, model)
            fit <- limma::contrasts.fit(fit, contrast_vector)
            fit <- limma::eBayes(fit, trend = TRUE, robust = TRUE)
            table <- limma::topTable(
                fit, coef = 1, number = Inf, sort.by = "P", adjust.method = "BH"
            )
            table <- data.frame(
                pathway = rownames(table),
                mean_numerator = rowMeans(
                    contrast_scores[
                        rownames(table), group == numerator, drop = FALSE
                    ]
                ),
                mean_denominator = rowMeans(
                    contrast_scores[
                        rownames(table), group == denominator, drop = FALSE
                    ]
                ),
                score_difference = table$logFC,
                t = table$t,
                pvalue = table$P.Value,
                padj = table$adj.P.Val,
                row.names = NULL,
                check.names = FALSE
            )
            significant <- table[!is.na(table$padj) & table$padj < 0.05, , drop = FALSE]
            contrast_dir <- file.path(
                args[["output-dir"]], "differential", method_name, contrast_id
            )
            dir.create(contrast_dir, recursive = TRUE, showWarnings = FALSE)
            write.table(
                table, file.path(contrast_dir, "complete_results.tsv"),
                sep = "\t", row.names = FALSE, quote = FALSE
            )
            write.table(
                significant, file.path(contrast_dir, "significant_padj_0.05.tsv"),
                sep = "\t", row.names = FALSE, quote = FALSE
            )
            png(file.path(contrast_dir, "volcano_plot.png"), width = 1800, height = 1500, res = 220)
            colours <- ifelse(
                !is.na(table$padj) & table$padj < 0.05, "#077F97", "#888888"
            )
            plot(
                table$score_difference,
                -log10(pmax(table$pvalue, .Machine$double.xmin)),
                col = colours, pch = 16,
                xlab = "Mean pathway-score difference",
                ylab = "-log10(p-value)",
                main = paste(method_name, numerator, "vs", denominator)
            )
            abline(v = 0, lty = 2, col = "#555555")
            dev.off()
            contrast_summaries[[length(contrast_summaries) + 1L]] <- data.frame(
                method = method_name,
                contrast_id = contrast_id,
                factor = factor_name,
                numerator = numerator,
                denominator = denominator,
                tested_pathways = nrow(table),
                significant_padj_0.05 = nrow(significant),
                stringsAsFactors = FALSE
            )
        }
    }
}

if (length(contrast_summaries)) {
    write.table(
        do.call(rbind, contrast_summaries),
        file.path(args[["output-dir"]], "differential_summary.tsv"),
        sep = "\t", row.names = FALSE, quote = FALSE
    )
}
metadata <- c(
    paste0("engine\tssGSVA ", as.character(packageVersion("ssGSVA"))),
    paste0("GSVA_version\t", as.character(packageVersion("GSVA"))),
    paste0("methods\t", paste(names(scores), collapse = ",")),
    paste0("collection\t", args$collection),
    paste0("gmt\t", normalizePath(args$gmt)),
    paste0("gmt_sha256\t", args[["gmt-sha256"]]),
    paste0("input_matrix\t", normalizePath(args$expression)),
    "input_value\tRSEM TPM",
    "gene_identifier\tgene_name",
    "duplicate_symbols\thighest-expression locus",
    paste0("design_used\t", if ("design" %in% names(args)) "true" else "false"),
    paste0(
        "differential_contrasts\t",
        if (length(contrast_summaries)) length(contrast_summaries) else 0
    )
)
writeLines(c("key\tvalue", metadata), file.path(args[["output-dir"]], "run_metadata.tsv"))
message("[ssgsva] Completed: ", args[["output-dir"]])
