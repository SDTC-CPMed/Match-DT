#!/usr/bin/env Rscript
# Run Prong 1 prefilter → matched RR → directionality.
#
# Usage (from project root):
#   Rscript --vanilla scripts/02_run_prong1_trajectories.R

args <- commandArgs(trailingOnly = TRUE)

parse_args <- function(args) {
  out <- list(prepared_dir = NULL, output_dir = NULL)
  i <- 1L
  while (i <= length(args)) {
    key <- args[[i]]
    if (!startsWith(key, "--") || i == length(args)) stop("Unexpected argument: ", key)
    val <- args[[i + 1L]]
    if (key == "--prepared-dir") out$prepared_dir <- val
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
source(file.path("src", "prong1", "trajectories.R"))

cfg <- prong1_load_config()
p1 <- cfg$prong1
root <- cfg$project_root

prepared_dir <- prong1_resolve_path(
  if (!is.null(cli$prepared_dir)) cli$prepared_dir else p1$prepared_dir, root
)
output_dir <- prong1_resolve_path(
  if (!is.null(cli$output_dir)) cli$output_dir else p1$output_dir, root
)

required <- c("participants.rds", "diagnoses_earliest.rds", "disease_n_patient.tsv")
missing <- required[!file.exists(file.path(prepared_dir, required))]
if (length(missing) > 0) {
  stop(
    "Prepared inputs missing in ", prepared_dir, ": ",
    paste(missing, collapse = ", "),
    ". Run scripts/01_prepare_prong1_input.R first."
  )
}

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
