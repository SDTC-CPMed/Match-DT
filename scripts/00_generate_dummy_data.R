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
    "--min-age", type = "integer", default = 51L,
    help = "Minimum age at baseline (inclusive) [default %default]"
  ),
  make_option(
    "--max-age", type = "integer", default = 75L,
    help = "Maximum age at baseline (inclusive) [default %default]"
  ),
  make_option(
    "--enroll-start", type = "character", default = "1998-01-01",
    help = "Baseline/assessment window start YYYY-MM-DD [default %default]"
  ),
  make_option(
    "--enroll-end", type = "character", default = "2015-12-31",
    help = "Baseline/assessment window end YYYY-MM-DD [default %default]"
  ),
  make_option(
    "--dirty", action = "store_true", default = FALSE,
    help = "Write obfuscated dirty EHR (default dir: data/raw/dummy_dirty)"
  ),
  make_option(
    "--output-dir", type = "character", default = NULL,
    help = "Output directory (default: data/raw/dummy or data/raw/dummy_dirty with --dirty)"
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
if (!is.integer(opt$min_age) || is.na(opt$min_age)) {
  stop("--min-age must be an integer.", call. = FALSE)
}
if (!is.integer(opt$max_age) || is.na(opt$max_age) || opt$max_age < opt$min_age) {
  stop("--max-age must be an integer >= --min-age.", call. = FALSE)
}
enroll_start <- as.Date(opt$enroll_start)
enroll_end <- as.Date(opt$enroll_end)
if (is.na(enroll_start) || is.na(enroll_end) || enroll_end < enroll_start) {
  stop("--enroll-start/--enroll-end must be valid dates with start <= end.", call. = FALSE)
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
# Prefer CLI output dir; otherwise clean → data/raw/dummy, dirty → data/raw/dummy_dirty.
output_dir <- if (!is.null(opt$output_dir)) {
  prong1_resolve_path(opt$output_dir, cfg$project_root)
} else if (isTRUE(opt$dirty)) {
  file.path(cfg$project_root, "data", "raw", "dummy_dirty")
} else {
  file.path(cfg$project_root, "data", "raw", "dummy")
}

gen_fun <- if (isTRUE(opt$dirty)) {
  prong1_generate_dirty_dummy_data
} else {
  prong1_generate_dummy_data
}

gen_fun(
  n_participants = opt$n,
  seed = opt$seed,
  output_dir = output_dir,
  censor_date = as.Date(cfg$prong1$censor_date),
  min_age = opt$min_age,
  max_age = opt$max_age,
  enroll_start = enroll_start,
  enroll_end = enroll_end
)

if (isTRUE(opt$dirty)) {
  message("Dirty raw has no column map. Derive one (see tests/fixtures/dummy_dirty_solution/ only for grading).")
  message("Next: map free-text dx_raw → ICD, then scripts/01_prepare_prong1_input.R")
} else {
  message("Next: Rscript --vanilla scripts/01_prepare_prong1_input.R")
}
