#!/usr/bin/env Rscript

options(
  repos = c(CRAN = "https://cloud.r-project.org"),
  warn = 1
)

args <- commandArgs(trailingOnly = TRUE)

project_root <- if (length(args) >= 1L) {
  normalizePath(args[[1]], mustWork = TRUE)
} else {
  normalizePath(getwd(), mustWork = TRUE)
}

lockfile <- file.path(project_root, "renv.lock")

message("Restoring renv environment")
message("Project root: ", project_root)
message("Lockfile:     ", lockfile)

if (!file.exists(lockfile)) {
  stop(
    "renv.lock was not found at:\n  ",
    lockfile,
    "\n\nRun setup/scripts/initialise_renv.R first to create it."
  )
}

if (!requireNamespace("renv", quietly = TRUE)) {
  message("Installing renv bootstrap package...")
  
  install.packages(
    "renv",
    repos = "https://cloud.r-project.org"
  )
}

renv::consent(provided = TRUE)

renv::restore(
  project = project_root,
  lockfile = lockfile,
  prompt = FALSE,
  clean = FALSE
)

message("renv environment restored successfully.")
