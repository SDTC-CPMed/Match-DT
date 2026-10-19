#!/usr/bin/env Rscript
# Generate seeded dummy EHR tables with non-canonical column names.
#
# Usage (from project root):
#   Rscript --vanilla scripts/00_generate_dummy_data.R
#   Rscript --vanilla scripts/00_generate_dummy_data.R --seed 42 --n 30000

args <- commandArgs(trailingOnly = TRUE)

parse_args <- function(args) {
  out <- list(seed = 42L, n = 30000L, output_dir = NULL)
  i <- 1L
  while (i <= length(args)) {
    key <- args[[i]]
    if (!startsWith(key, "--") || i == length(args)) stop("Unexpected argument: ", key)
    val <- args[[i + 1L]]
    if (key == "--seed") out$seed <- as.integer(val)
    else if (key == "--n") out$n <- as.integer(val)
    else if (key == "--output-dir") out$output_dir <- val
    else stop("Unknown flag: ", key)
    i <- i + 2L
  }
  out
}

cli <- parse_args(args)

script_path <- local({
  ca <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", ca[startsWith(ca, "--file=")])
  if (length(f) == 1L && nzchar(f)) normalizePath(f) else NULL
})
if (!is.null(script_path)) {
  setwd(normalizePath(file.path(dirname(script_path), "..")))
}

source(file.path("src", "prong1", "prepare_input.R"))
source(file.path("src", "prong1", "generate_dummy.R"))

cfg <- prong1_load_config()
output_dir <- if (!is.null(cli$output_dir)) {
  prong1_resolve_path(cli$output_dir, cfg$project_root)
} else {
  file.path(cfg$project_root, "data", "raw", "dummy")
}

prong1_generate_dummy_data(
  n_participants = cli$n,
  seed = cli$seed,
  output_dir = output_dir,
  censor_date = as.Date(cfg$prong1$censor_date)
)

message("Next: Rscript --vanilla scripts/01_prepare_prong1_input.R")
