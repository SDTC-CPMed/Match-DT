#!/usr/bin/env Rscript
# Post-run QC for prepared tables, trajectories, and bubble plot.
#
# Usage:
#   Rscript --vanilla scripts/verify_prong1_run.R --expect-seed42
#   Rscript --vanilla scripts/verify_prong1_run.R \
#     --prepared-dir data/processed/prong1_input_dirty \
#     --trajectories-dir data/processed/prong1_trajectories_dirty \
#     --figure-png reports/figures/prong1_dirty_bubble.png

suppressPackageStartupMessages(library(optparse))

option_list <- list(
  make_option("--config", type = "character", default = NULL),
  make_option("--prepared-dir", type = "character", default = NULL),
  make_option("--trajectories-dir", type = "character", default = NULL),
  make_option("--figure-png", type = "character", default = NULL),
  make_option("--icd-map-json", type = "character", default = NULL),
  make_option("--expect-seed42", action = "store_true", default = FALSE,
              help = "Expect non-empty Final_trajectories for default seed-42 demo")
)

opt <- parse_args(
  OptionParser(
    usage = "Rscript --vanilla scripts/verify_prong1_run.R [options]",
    option_list = option_list
  ),
  convert_hyphens_to_underscores = TRUE
)

script_path <- local({
  ca <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", ca[startsWith(ca, "--file=")])
  if (length(f) == 1L && nzchar(f)) normalizePath(f) else NULL
})
if (!is.null(script_path)) {
  setwd(normalizePath(file.path(dirname(script_path), "..")))
}

source(file.path("src", "prong1", "prepare_input.R"))

cfg <- prong1_load_config(config_path = opt$config)
root <- cfg$project_root
p1 <- cfg$prong1

prepared_dir <- prong1_resolve_path(
  if (!is.null(opt$prepared_dir)) opt$prepared_dir else p1$prepared_dir, root
)
traj_dir <- prong1_resolve_path(
  if (!is.null(opt$trajectories_dir)) opt$trajectories_dir else p1$output_dir, root
)
fig <- prong1_resolve_path(
  if (!is.null(opt$figure_png)) opt$figure_png else "reports/figures/prong1_rr_vs_years_bubble.png",
  root
)
icd_map <- prong1_resolve_path(opt$icd_map_json, root)

ok <- TRUE
fail <- function(...) {
  message("FAIL: ", paste0(...))
  ok <<- FALSE
}

message("=== verify_prong1_run ===")
message("prepared: ", prepared_dir)
message("trajectories: ", traj_dir)
message("figure: ", fig)

prep_report <- file.path(prepared_dir, "prep_report.json")
if (!file.exists(prep_report)) {
  fail("missing prep_report.json")
} else {
  rep <- jsonlite::fromJSON(prep_report)
  if (isFALSE(rep$ready) || identical(rep$ready, FALSE)) {
    fail("prep_report ready is false")
  } else if (is.null(rep$ready) && (is.null(rep$n_participants_out) || rep$n_participants_out < 1)) {
    fail("prep_report looks empty / not ready")
  } else {
    message("  prep_report: participants_out=", rep$n_participants_out,
            " diagnoses_earliest=", rep$n_diagnoses_earliest_out)
  }
  if (!is.null(rep$n_unconfirmed_icd_mappings) && rep$n_unconfirmed_icd_mappings > 0) {
    message("  WARNING: unconfirmed ICD mappings=", rep$n_unconfirmed_icd_mappings)
  }
}

dnp <- file.path(prepared_dir, "disease_n_patient.tsv")
if (!file.exists(dnp)) {
  fail("missing disease_n_patient.tsv")
} else {
  dn <- readr::read_tsv(dnp, show_col_types = FALSE)
  bad <- dn$icd10[!grepl("^[A-Z][0-9]{2}$", dn$icd10)]
  if (length(bad) > 0) {
    fail("fake/non-level3 ICD codes in disease_n_patient: ", paste(unique(bad), collapse = ", "))
  } else {
    message("  disease_n_patient ICD codes: OK (", nrow(dn), " diseases)")
  }
}

finals <- file.path(traj_dir, "Final_trajectories.csv")
if (!file.exists(finals)) {
  fail("missing Final_trajectories.csv")
} else {
  ft <- readr::read_csv(finals, show_col_types = FALSE)
  need <- c("D1", "D2", "RR")
  miss <- setdiff(need, names(ft))
  if (length(miss) > 0 && nrow(ft) > 0) {
    fail("Final_trajectories missing columns: ", paste(miss, collapse = ", "))
  } else {
    message("  Final_trajectories rows: ", nrow(ft))
  }
  if (isTRUE(opt$expect_seed42) && nrow(ft) < 1) {
    fail("--expect-seed42 but Final_trajectories is empty")
  }
}

if (!file.exists(fig)) {
  fail("missing figure PNG: ", fig)
} else {
  message("  figure exists: ", file.info(fig)$size, " bytes")
}

if (!is.null(icd_map) && file.exists(icd_map)) {
  info <- prong1_load_icd_map_json(icd_map)
  n_unconf <- 0L
  for (m in info$mappings) {
    if (!isTRUE(m$confirmed) && !is.null(m$icd10) && nzchar(as.character(m$icd10))) {
      n_unconf <- n_unconf + 1L
    }
  }
  if (n_unconf > 0) {
    message("  WARNING: ICD map has ", n_unconf, " unconfirmed non-null entries: ", icd_map)
  }
}

if (!ok) {
  message("VERIFY: NO")
  quit(status = 1)
}
message("VERIFY: YES")
