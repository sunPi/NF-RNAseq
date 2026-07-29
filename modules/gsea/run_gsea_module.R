#!/usr/bin/env Rscript

fail <- function(...) {
    message("[gsea] ERROR: ", paste0(..., collapse = ""))
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
    "dge-dir", "contrasts", "gmt", "collection", "gmt-sha256", "output-dir"
)
missing <- required[!required %in% names(args)]
if (length(missing)) fail("Missing arguments: ", paste(missing, collapse = ", "))
if (!requireNamespace("dqGSEA", quietly = TRUE)) {
    fail("Embedded R package dqGSEA is not installed")
}

contrasts <- read.delim(
    args$contrasts, check.names = FALSE, stringsAsFactors = FALSE,
    quote = "", comment.char = ""
)
required_columns <- c("contrast_id", "factor", "numerator", "denominator")
if (!all(required_columns %in% names(contrasts)) || !nrow(contrasts)) {
    fail("Contrast table is empty or missing required columns")
}

output_dir <- args[["output-dir"]]
dir.create(file.path(output_dir, "contrasts"), recursive = TRUE, showWarnings = FALSE)
summary_rows <- vector("list", nrow(contrasts))

for (index in seq_len(nrow(contrasts))) {
    contrast <- contrasts[index, , drop = FALSE]
    contrast_id <- contrast$contrast_id[[1L]]
    dge_path <- file.path(
        args[["dge-dir"]], contrast_id, "complete_results.tsv"
    )
    if (!file.exists(dge_path)) {
        fail("DGE result missing for contrast ", contrast_id, ": ", dge_path)
    }
    contrast_dir <- file.path(output_dir, "contrasts", contrast_id)
    dqGSEA::run_dqgsea(
        dge_path = dge_path,
        gmt_path = args$gmt,
        output_dir = contrast_dir,
        padj_threshold = 0.05,
        gene_column = "gene_name",
        rank_column = "stat",
        min_size = 10L,
        max_size = 500L
    )
    complete <- read.csv(
        file.path(contrast_dir, "gsea.csv"),
        check.names = FALSE, stringsAsFactors = FALSE
    )
    significant <- read.csv(
        file.path(contrast_dir, "gsea_significant.csv"),
        check.names = FALSE, stringsAsFactors = FALSE
    )
    summary_rows[[index]] <- data.frame(
        contrast_id = contrast_id,
        factor = contrast$factor[[1L]],
        numerator = contrast$numerator[[1L]],
        denominator = contrast$denominator[[1L]],
        tested_pathways = nrow(complete),
        significant_padj_0.05 = nrow(significant),
        stringsAsFactors = FALSE
    )
}

write.table(
    do.call(rbind, summary_rows), file.path(output_dir, "contrast_summary.tsv"),
    sep = "\t", row.names = FALSE, quote = FALSE
)
metadata <- c(
    paste0("engine\tdqGSEA ", as.character(packageVersion("dqGSEA"))),
    paste0("fgsea_version\t", as.character(packageVersion("fgsea"))),
    paste0("collection\t", args$collection),
    paste0("gmt\t", normalizePath(args$gmt)),
    paste0("gmt_sha256\t", args[["gmt-sha256"]]),
    "gene_identifier\tgene_name",
    "ranking_statistic\tDGE Wald statistic (stat)",
    "significance\tBenjamini-Hochberg adjusted p-value <= 0.05",
    "mode\tranked_contrast"
)
writeLines(c("key\tvalue", metadata), file.path(output_dir, "run_metadata.tsv"))
message("[gsea] Completed ", nrow(contrasts), " contrast(s): ", output_dir)
