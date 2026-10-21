#!/usr/bin/env Rscript
# Prepare generic EHR tables for Prong 1 trajectory analysis.
#
# Usage (from project root):
#   Rscript --vanilla scripts/01_prepare_prong1_input.R --help

suppressPackageStartupMessages(library(optparse))

# Path overrides. NULL falls back to config.yaml.
option_list <- list(
  make_option("--participants", type = "character", default = NULL,
              help = "Participants table (default: config)"),
  make_option("--diagnoses", type = "character", default = NULL,
              help = "Diagnoses table (default: config)"),
  make_option("--dictionary", type = "character", default = NULL,
              help = "Disease dictionary (default: config)"),
  make_option("--column-map", type = "character", default = NULL,
              help = "Column-map YAML (default: config)"),
  make_option("--output-dir", type = "character", default = NULL,
              help = "Prepared-output directory (default: config)")
)

# convert_hyphens_to_underscores: --column-map becomes opt$column_map.
opt <- parse_args(
  OptionParser(
    usage = "Rscript --vanilla scripts/01_prepare_prong1_input.R [options]",
    description = "Prepare generic EHR tables for Prong 1 trajectory analysis.",
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

cfg <- prong1_load_config()
p1 <- cfg$prong1
root <- cfg$project_root

# Resolve each input/output path: CLI wins, else config relative to project root.
participants_path <- prong1_resolve_path(
  if (!is.null(opt$participants)) opt$participants else p1$participants_file, root
)
diagnoses_path <- prong1_resolve_path(
  if (!is.null(opt$diagnoses)) opt$diagnoses else p1$diagnoses_file, root
)
dictionary_path <- prong1_resolve_path(
  if (!is.null(opt$dictionary)) opt$dictionary else p1$disease_dictionary_file, root
)
column_map_path <- prong1_resolve_path(
  if (!is.null(opt$column_map)) opt$column_map else p1$column_map_file, root
)
output_dir <- prong1_resolve_path(
  if (!is.null(opt$output_dir)) opt$output_dir else p1$prepared_dir, root
)

result <- prong1_prepare_input(
  participants_path = participants_path,
  diagnoses_path = diagnoses_path,
  dictionary_path = dictionary_path,
  column_map_path = column_map_path,
  n_patient_min = as.integer(p1$n_patient_min),
  output_dir = output_dir
)

prong1_print_prep_checklist(result$report, output_dir)
message("Next: Rscript --vanilla scripts/02_run_prong1_trajectories.R")
