#!/usr/bin/env Rscript

fail <- function(...) {
    message("[go] ERROR: ", paste0(..., collapse = ""))
    quit(status = 1)
}

parse_args <- function(values) {
    result <- list()
    index <- 1L
    while (index <= length(values)) {
        key <- values[[index]]
        if (!startsWith(key, "--") || index == length(values)) fail("Invalid arguments")
        result[[substring(key, 3L)]] <- values[[index + 1L]]
        index <- index + 2L
    }
    result
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
required <- c("dge-dir", "contrasts", "output-dir", "threads")
missing <- required[!required %in% names(args)]
if (length(missing)) fail("Missing arguments: ", paste(missing, collapse = ", "))

packages <- c("clusterProfiler", "enrichplot", "org.Hs.eg.db", "ggplot2")
unavailable <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(unavailable)) fail("Missing R packages: ", paste(unavailable, collapse = ", "))

contrasts <- read.delim(args$contrasts, check.names = FALSE, stringsAsFactors = FALSE,
                        quote = "", comment.char = "")
required_columns <- c("contrast_id", "factor", "numerator", "denominator")
if (!all(required_columns %in% names(contrasts)) || !nrow(contrasts)) {
    fail("Contrast table is empty or missing required columns")
}

output_dir <- args[["output-dir"]]
dir.create(file.path(output_dir, "contrasts"), recursive = TRUE, showWarnings = FALSE)
summary_rows <- vector("list", nrow(contrasts))
set.seed(1L)

for (index in seq_len(nrow(contrasts))) {
    contrast <- contrasts[index, , drop = FALSE]
    contrast_id <- contrast$contrast_id[[1L]]
    dge_path <- file.path(args[["dge-dir"]], contrast_id,
                          "complete_results.symbol_highest.tsv")
    if (!file.exists(dge_path)) fail("DGE result missing for ", contrast_id, ": ", dge_path)

    dge <- read.delim(dge_path, check.names = FALSE, stringsAsFactors = FALSE)
    needed <- c("gene_name", "log2FoldChange")
    if (!all(needed %in% names(dge))) fail("DGE table lacks gene_name/log2FoldChange: ", dge_path)
    keep <- !is.na(dge$gene_name) & nzchar(dge$gene_name) &
        is.finite(dge$log2FoldChange)
    ranks <- dge$log2FoldChange[keep]
    names(ranks) <- dge$gene_name[keep]
    ranks <- sort(ranks, decreasing = TRUE)
    if (length(ranks) < 10L) fail("Fewer than 10 ranked genes for contrast ", contrast_id)

    contrast_dir <- file.path(output_dir, "contrasts", contrast_id)
    dir.create(contrast_dir, recursive = TRUE, showWarnings = FALSE)
    result_rds <- file.path(contrast_dir, "gseGO.rds")
    if (file.exists(result_rds) && file.mtime(result_rds) >= file.mtime(dge_path)) {
        message("[go] Reusing current enrichment result for ", contrast_id)
        result <- readRDS(result_rds)
    } else {
        result <- suppressMessages(clusterProfiler::gseGO(
            geneList = ranks, ont = "ALL", keyType = "SYMBOL",
            minGSSize = 3L, maxGSSize = 800L, pvalueCutoff = 1,
            verbose = FALSE, OrgDb = org.Hs.eg.db::org.Hs.eg.db,
            pAdjustMethod = "BH", by = "fgsea", seed = TRUE, eps = 1e-10
        ))
        saveRDS(result, result_rds)
    }
    result_table <- as.data.frame(result)
    significant <- result_table[
        !is.na(result_table$p.adjust) & result_table$p.adjust <= 0.05, , drop = FALSE
    ]

    write.table(result_table, file.path(contrast_dir, "gseGO.tsv"), sep = "\t",
                row.names = FALSE, quote = FALSE)
    write.table(significant, file.path(contrast_dir, "gseGO_significant.tsv"), sep = "\t",
                row.names = FALSE, quote = FALSE)

    if (nrow(result_table)) {
        plot <- enrichplot::dotplot(result, showCategory = 10, split = ".sign") +
            ggplot2::facet_grid(. ~ .sign) +
            ggplot2::labs(title = paste0(contrast$numerator[[1L]], " vs ",
                                         contrast$denominator[[1L]]))
        ggplot2::ggsave(file.path(contrast_dir, "GO_dotplot.png"), plot,
                        width = 10, height = 8, dpi = 300)
        ggplot2::ggsave(file.path(contrast_dir, "GO_dotplot.pdf"), plot,
                        width = 10, height = 8)
    }

    summary_rows[[index]] <- data.frame(
        contrast_id = contrast_id,
        factor = contrast$factor[[1L]],
        numerator = contrast$numerator[[1L]],
        denominator = contrast$denominator[[1L]],
        tested_terms = nrow(result_table),
        significant_padj_0.05 = nrow(significant), stringsAsFactors = FALSE
    )
}

write.table(do.call(rbind, summary_rows), file.path(output_dir, "contrast_summary.tsv"),
            sep = "\t", row.names = FALSE, quote = FALSE)
metadata <- c(
    paste0("clusterProfiler_version\t", as.character(packageVersion("clusterProfiler"))),
    paste0("org.Hs.eg.db_version\t", as.character(packageVersion("org.Hs.eg.db"))),
    "ontology\tALL (BP, CC, MF)", "gene_identifier\tHUGO symbol",
    "duplicate_symbols\thighest DESeq2 baseMean selected by DGE",
    "ranking_statistic\tDGE log2FoldChange", "adjustment\tBenjamini-Hochberg",
    "significance\tadjusted p-value <= 0.05", "fgsea_eps\t1e-10",
    "engine\tclusterProfiler gseGO/fgsea"
)
writeLines(c("key\tvalue", metadata), file.path(output_dir, "run_metadata.tsv"))
message("[go] Completed ", nrow(contrasts), " contrast(s): ", output_dir)
