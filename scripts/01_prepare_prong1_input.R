#!/usr/bin/env Rscript
# Prepare generic EHR tables for Prong 1 trajectory analysis.
#
# Usage (from project root):
#   Rscript --vanilla scripts/01_prepare_prong1_input.R

args <- commandArgs(trailingOnly = TRUE)

parse_args <- function(args) {
  out <- list(
    participants = NULL,
    diagnoses = NULL,
    dictionary = NULL,
    column_map = NULL,
    output_dir = NULL
  )
  i <- 1L
  while (i <= length(args)) {
    key <- args[[i]]
    if (!startsWith(key, "--") || i == length(args)) stop("Unexpected argument: ", key)
    val <- args[[i + 1L]]
    if (key == "--participants") out$participants <- val
    else if (key == "--diagnoses") out$diagnoses <- val
    else if (key == "--dictionary") out$dictionary <- val
    else if (key == "--column-map") out$column_map <- val
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

cfg <- prong1_load_config()
p1 <- cfg$prong1
root <- cfg$project_root

participants_path <- prong1_resolve_path(
  if (!is.null(cli$participants)) cli$participants else p1$participants_file, root
)
diagnoses_path <- prong1_resolve_path(
  if (!is.null(cli$diagnoses)) cli$diagnoses else p1$diagnoses_file, root
)
dictionary_path <- prong1_resolve_path(
  if (!is.null(cli$dictionary)) cli$dictionary else p1$disease_dictionary_file, root
)
column_map_path <- prong1_resolve_path(
  if (!is.null(cli$column_map)) cli$column_map else p1$column_map_file, root
)
output_dir <- prong1_resolve_path(
  if (!is.null(cli$output_dir)) cli$output_dir else p1$prepared_dir, root
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
