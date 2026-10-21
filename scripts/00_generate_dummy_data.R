#!/usr/bin/env Rscript
# Generate seeded dummy EHR tables with non-canonical column names.
#
# Usage (from project root):
#   Rscript --vanilla scripts/00_generate_dummy_data.R --help
#   Rscript --vanilla scripts/00_generate_dummy_data.R --seed 42 --n 30000

suppressPackageStartupMessages(library(optparse))

# Optional overrides. --output-dir NULL means data/raw/dummy under the project root.
option_list <- list(
  make_option(
    "--seed", type = "integer", default = 42L,
    help = "RNG seed [default %default]"
  ),
  make_option(
    "--n", type = "integer", default = 30000L,
    help = "Number of participants [default %default]"
  ),
  make_option(
    "--output-dir", type = "character", default = NULL,
    help = "Output directory (default: data/raw/dummy)"
  )
)

# convert_hyphens_to_underscores: --output-dir becomes opt$output_dir.
opt <- parse_args(
  OptionParser(
    usage = "Rscript --vanilla scripts/00_generate_dummy_data.R [options]",
    description = "Generate seeded dummy EHR tables with non-canonical column names.",
    option_list = option_list
  ),
  convert_hyphens_to_underscores = TRUE
)

# optparse warns and keeps a non-integer string; stop before generating data.
if (!is.integer(opt$seed) || is.na(opt$seed)) {
  stop("--seed must be an integer.", call. = FALSE)
}
if (!is.integer(opt$n) || is.na(opt$n) || opt$n < 1L) {
  stop("--n must be a positive integer.", call. = FALSE)
}

# When launched via Rscript, cd to the repo root (parent of scripts/).
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
# Prefer CLI output dir; otherwise write under data/raw/dummy.
output_dir <- if (!is.null(opt$output_dir)) {
  prong1_resolve_path(opt$output_dir, cfg$project_root)
} else {
  file.path(cfg$project_root, "data", "raw", "dummy")
}

prong1_generate_dummy_data(
  n_participants = opt$n,
  seed = opt$seed,
  output_dir = output_dir,
  censor_date = as.Date(cfg$prong1$censor_date)
)

message("Next: Rscript --vanilla scripts/01_prepare_prong1_input.R")
