#!/usr/bin/env Rscript
# Run Prong 1 prefilter → matched RR → directionality.
#
# Usage (from project root):
#   Rscript --vanilla scripts/02_run_prong1_trajectories.R --help

suppressPackageStartupMessages(library(optparse))

# Optional CLI: --prepared-dir, --output-dir (else from config.yaml).
option_list <- list(
  make_option("--prepared-dir", type = "character", default = NULL,
              help = "Prepared input directory (default: config)"),
  make_option("--output-dir", type = "character", default = NULL,
              help = "Trajectory output directory (default: config)")
)

# convert_hyphens_to_underscores: --prepared-dir becomes opt$prepared_dir.
opt <- parse_args(
  OptionParser(
    usage = "Rscript --vanilla scripts/02_run_prong1_trajectories.R [options]",
    description = "Run Prong 1 prefilter, matched relative risk, and directionality.",
    option_list = option_list
  ),
  convert_hyphens_to_underscores = TRUE
)

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
source(file.path("src", "prong1", "trajectories.R"))

cfg <- prong1_load_config()
p1 <- cfg$prong1
root <- cfg$project_root

prepared_dir <- prong1_resolve_path(
  if (!is.null(opt$prepared_dir)) opt$prepared_dir else p1$prepared_dir, root
)
output_dir <- prong1_resolve_path(
  if (!is.null(opt$output_dir)) opt$output_dir else p1$output_dir, root
)

# Fail fast if prep step was skipped / incomplete.
required <- c("participants.rds", "diagnoses_earliest.rds", "disease_n_patient.tsv")
missing <- required[!file.exists(file.path(prepared_dir, required))]
if (length(missing) > 0) {
  stop(
    "Prepared inputs missing in ", prepared_dir, ": ",
    paste(missing, collapse = ", "),
    ". Run scripts/01_prepare_prong1_input.R first."
  )
}

# All analysis thresholds come from config$prong1.
prong1_run_trajectories(
  prepared_dir = prepared_dir,
  output_dir = output_dir,
  censor_date = p1$censor_date,
  n_patient_min = as.integer(p1$n_patient_min),
  min_comorbid_overlap = as.integer(p1$min_comorbid_overlap),
  match_ratio = as.integer(p1$match_ratio),
  assessment_year_caliper = as.numeric(p1$assessment_year_caliper),
  prefilter_fdr = as.numeric(p1$prefilter_fdr),
  rr_fdr = as.numeric(p1$rr_fdr),
  direction_fdr = as.numeric(p1$direction_fdr),
  pair_scope = if (is.null(p1$pair_scope)) "disease_oi" else p1$pair_scope,
  exclude_d1_letters = unlist(p1$exclude_d1_letters),
  disease_oi = unlist(p1$disease_oi)
)

message("Done. Outputs in ", output_dir)
message("Next: Rscript --vanilla scripts/03_plot_prong1_rr_bubble.R")
