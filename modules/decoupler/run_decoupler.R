#!/usr/bin/env Rscript

fail <- function(...) stop(paste0(...), call. = FALSE)

values <- commandArgs(trailingOnly = TRUE)
args <- list()
while (length(values)) {
    if (length(values) < 2L || !startsWith(values[[1L]], "--")) fail("Invalid arguments")
    args[[sub("^--", "", values[[1L]])]] <- values[[2L]]
    values <- values[-c(1L, 2L)]
}
for (key in c("expression", "collectri", "progeny", "output-dir", "threads")) {
    if (is.null(args[[key]])) fail("Missing --", key)
}
threads <- suppressWarnings(as.integer(args$threads))
if (is.na(threads) || threads < 1L) fail("--threads must be a positive integer")

dir.create(args[["output-dir"]], recursive = TRUE, showWarnings = FALSE)
message("[decoupler] Reading expression matrix")
expression <- read.delim(args$expression, check.names = FALSE)
samples <- setdiff(names(expression), c("gene_id", "gene_name", "gene_type"))
if (!length(samples)) fail("Expression matrix has no sample columns")
mat <- as.matrix(expression[, samples, drop = FALSE])
storage.mode(mat) <- "numeric"
rownames(mat) <- expression$gene_name
mat <- log2(mat + 1)
keep <- rowSums(mat) > 0 & apply(mat, 1L, stats::var) > 0
mat <- mat[keep, , drop = FALSE]
message("[decoupler] Retained ", nrow(mat), " variable expressed genes across ",
        ncol(mat), " samples")

to_matrix <- function(result) {
    wide <- xtabs(score ~ source + condition, result)
    as.matrix(wide)
}

# decoupleR 2.8.0 run_ulm() constructs a dense genes-by-all-regulators matrix
# and fits an unused joint model. This vectorized implementation calculates the
# identical t statistic for each independent y ~ regulator regression, while
# retaining only genes represented in the network.
vectorized_ulm <- function(input, network, minsize = 5L) {
    network <- network[network$target %in% rownames(input), , drop = FALSE]
    sizes <- table(network$source)
    network <- network[network$source %in% names(sizes[sizes >= minsize]), , drop = FALSE]
    if (!nrow(network)) fail("CollecTRI network is empty after expression filtering")

    targets <- intersect(rownames(input), unique(network$target))
    input <- input[targets, , drop = FALSE]
    sources <- sort(unique(network$source))
    weights <- Matrix::sparseMatrix(
        i = match(network$target, targets),
        j = match(network$source, sources),
        x = network$mor,
        dims = c(length(targets), length(sources)),
        dimnames = list(targets, sources)
    )

    n <- nrow(input)
    sum_x <- Matrix::colSums(weights)
    sum_y <- colSums(input)
    cross_xy <- as.matrix(Matrix::crossprod(weights, input)) - outer(sum_x, sum_y) / n
    ss_x <- Matrix::colSums(weights ^ 2) - (sum_x ^ 2) / n
    ss_y <- colSums(input ^ 2) - (sum_y ^ 2) / n
    denominator <- sqrt(outer(ss_x, ss_y))
    correlation <- cross_xy / denominator
    correlation[correlation > 1] <- 1
    correlation[correlation < -1] <- -1
    statistic <- correlation * sqrt((n - 2) / pmax(1 - correlation ^ 2, .Machine$double.eps))
    rownames(statistic) <- sources
    colnames(statistic) <- colnames(input)
    statistic
}

differential <- function(out, scores) {
    design <- read.delim(args$design, check.names = FALSE)
    contrasts <- read.delim(args$contrasts, check.names = FALSE)
    for (index in seq_len(nrow(contrasts))) {
        contrast <- contrasts[index, , drop = FALSE]
        keep <- design[[contrast$factor]] %in% c(contrast$numerator, contrast$denominator)
        subset_design <- design[keep, , drop = FALSE]
        missing_samples <- setdiff(subset_design$sample, colnames(scores))
        if (length(missing_samples)) fail("Activity matrix is missing design samples: ",
                                          paste(missing_samples, collapse = ", "))
        response <- scores[, subset_design$sample, drop = FALSE]
        group <- relevel(factor(subset_design[[contrast$factor]]), contrast$denominator)
        model <- model.matrix(~ group)
        fit <- limma::eBayes(limma::lmFit(response, model))
        table <- limma::topTable(fit, coef = 2L, number = Inf, sort.by = "P")
        table$regulator <- rownames(table)
        table <- table[, c("regulator", setdiff(names(table), "regulator"))]
        contrast_dir <- file.path(out, "differential", contrast$contrast_id)
        dir.create(contrast_dir, recursive = TRUE, showWarnings = FALSE)
        write.table(table, file.path(contrast_dir, "complete_results.tsv"), sep = "\t",
                    quote = FALSE, row.names = FALSE)
        significant <- table[!is.na(table$adj.P.Val) & table$adj.P.Val < 0.05, , drop = FALSE]
        write.table(significant, file.path(contrast_dir, "significant_padj_0.05.tsv"),
                    sep = "\t", quote = FALSE, row.names = FALSE)
        top <- head(table[order(abs(table$logFC), decreasing = TRUE), ], 25L)
        plot <- ggplot2::ggplot(
            top, ggplot2::aes(stats::reorder(regulator, logFC), logFC, fill = logFC)
        ) + ggplot2::geom_col() + ggplot2::coord_flip() +
            ggplot2::scale_fill_gradient2(low = "#400257", mid = "white", high = "#077f97") +
            ggplot2::labs(x = NULL, y = "Differential activity", title = contrast$numerator) +
            ggprism::theme_prism()
        ggplot2::ggsave(file.path(contrast_dir, "activity_waterfall.png"), plot,
                        width = 8, height = 7, dpi = 300)
    }
}

write_scores <- function(out, scores) {
    write.table(cbind(regulator = rownames(scores), scores),
                file.path(out, "activity_scores.tsv"), sep = "\t",
                quote = FALSE, row.names = FALSE)
}

run_collectri <- function(network) {
    out <- file.path(args[["output-dir"]], "collectri_ulm")
    dir.create(out, recursive = TRUE, showWarnings = FALSE)
    score_file <- file.path(out, "activity_scores.tsv")
    if (file.exists(score_file) && file.mtime(score_file) >=
        max(file.mtime(args$expression), file.mtime(args$collectri))) {
        message("[decoupler] Reusing current CollecTRI ULM activities")
        stored <- read.delim(score_file, check.names = FALSE)
        scores <- as.matrix(stored[, -1L, drop = FALSE])
        rownames(scores) <- stored[[1L]]
    } else {
        message("[decoupler] Calculating vectorized CollecTRI ULM activities")
        scores <- vectorized_ulm(mat, network)
        write_scores(out, scores)
        message("[decoupler] Wrote CollecTRI activities: ", score_file)
    }
    if (!is.null(args$design)) differential(out, scores)
}

run_progeny <- function(network) {
    out <- file.path(args[["output-dir"]], "progeny_mlm")
    dir.create(out, recursive = TRUE, showWarnings = FALSE)
    score_file <- file.path(out, "activity_scores.tsv")
    if (file.exists(score_file) && file.mtime(score_file) >=
        max(file.mtime(args$expression), file.mtime(args$progeny))) {
        message("[decoupler] Reusing current PROGENy MLM activities")
        stored <- read.delim(score_file, check.names = FALSE)
        scores <- as.matrix(stored[, -1L, drop = FALSE])
        rownames(scores) <- stored[[1L]]
    } else {
        message("[decoupler] Calculating PROGENy MLM activities")
        network <- network[order(network$source, network$target, network$p_value), , drop = FALSE]
        network <- network[!duplicated(network[c("source", "target")]), , drop = FALSE]
        network <- network[network$target %in% rownames(mat), , drop = FALSE]
        resource_mat <- mat[rownames(mat) %in% unique(network$target), , drop = FALSE]
        result <- decoupleR::run_mlm(
            resource_mat, network, .source = "source", .target = "target",
            .mor = "weight", minsize = 5L, sparse = TRUE
        )
        scores <- to_matrix(result)
        write_scores(out, scores)
        message("[decoupler] Wrote PROGENy activities: ", score_file)
    }
    if (!is.null(args$design)) differential(out, scores)
}

run_collectri(readRDS(args$collectri))
run_progeny(readRDS(args$progeny))
writeLines(c(
    "key\tvalue", "expression\tlog2(TPM+1)",
    "collectri_method\tvectorized ULM (equivalent independent linear-model t statistic)",
    "progeny_method\tdecoupleR MLM", paste0("threads\t", threads),
    paste0("decoupleR_version\t", as.character(packageVersion("decoupleR")))
), file.path(args[["output-dir"]], "run_metadata.tsv"))
message("[decoupler] Completed: ", args[["output-dir"]])
