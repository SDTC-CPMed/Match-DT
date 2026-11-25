#!/usr/bin/env Rscript
# Preflight check for Prong 1: R version, packages, and key project paths.
#
# Usage (from project root):
#   Rscript --vanilla scripts/check_prong1_env.R
#   Rscript --vanilla scripts/check_prong1_env.R --install

suppressPackageStartupMessages({
  # optparse is itself a required dep; fall back to bare args if missing.
  has_optparse <- requireNamespace("optparse", quietly = TRUE)
})

args <- commandArgs(trailingOnly = TRUE)
do_install <- "--install" %in% args

if (has_optparse) {
  option_list <- list(
    optparse::make_option(
      "--install", action = "store_true", default = FALSE,
      help = "Install missing required CRAN packages"
    )
  )
  opt <- optparse::parse_args(
    optparse::OptionParser(
      usage = "Rscript --vanilla scripts/check_prong1_env.R [options]",
      description = "Check R version, packages, and Prong 1 project paths.",
      option_list = option_list
    )
  )
  do_install <- isTRUE(opt$install)
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

required_pkgs <- c(
  "dplyr", "readr", "yaml", "jsonlite", "stringr",
  "MatchIt", "ggplot2", "ggrepel", "optparse"
)
optional_pkgs <- character(0)

required_paths <- c(
  "config/config.yaml",
  "scripts/00_generate_dummy_data.R",
  "scripts/00b_map_diagnoses.R",
  "scripts/01_prepare_prong1_input.R",
  "scripts/02_run_prong1_trajectories.R",
  "scripts/03_plot_prong1_rr_bubble.R",
  "scripts/profile_ehr_inputs.R",
  "scripts/verify_prong1_run.R",
  "src/prong1/prepare_input.R",
  "src/prong1/trajectories.R",
  "src/prong1/generate_dummy.R",
  "src/prong1/plot_bubble.R",
  "skills/prong1-trajectories/SKILL.md"
)

ok <- TRUE
issues <- character(0)

# --- R version ---
r_ver <- getRversion()
message("R version: ", as.character(r_ver))
if (r_ver < "4.2.0") {
  ok <- FALSE
  issues <- c(issues, paste0("R >= 4.2 required (found ", r_ver, ")"))
  message("  FAIL: need R >= 4.2")
} else {
  message("  OK: R >= 4.2")
}

# --- Packages ---
missing_required <- required_pkgs[!vapply(
  required_pkgs, requireNamespace, logical(1), quietly = TRUE
)]
missing_optional <- optional_pkgs[!vapply(
  optional_pkgs, requireNamespace, logical(1), quietly = TRUE
)]

if (length(missing_required) > 0) {
  message("Missing required packages: ", paste(missing_required, collapse = ", "))
  if (do_install) {
    message("Installing missing required packages from CRAN…")
    utils::install.packages(
      missing_required,
      repos = "https://cloud.r-project.org"
    )
    still_missing <- missing_required[!vapply(
      missing_required, requireNamespace, logical(1), quietly = TRUE
    )]
    if (length(still_missing) > 0) {
      ok <- FALSE
      issues <- c(issues, paste0("Still missing after install: ", paste(still_missing, collapse = ", ")))
      message("  FAIL: could not install: ", paste(still_missing, collapse = ", "))
    } else {
      message("  OK: required packages installed")
    }
  } else {
    ok <- FALSE
    issues <- c(issues, paste0("Missing packages: ", paste(missing_required, collapse = ", ")))
    message("  FAIL: install with --install or README install command")
  }
} else {
  message("Required packages: OK (", paste(required_pkgs, collapse = ", "), ")")
}

if (length(optional_pkgs) > 0) {
  if (length(missing_optional) > 0) {
    message("Optional packages missing: ", paste(missing_optional, collapse = ", "), " — warn only")
  } else {
    message("Optional packages: OK (", paste(optional_pkgs, collapse = ", "), ")")
  }
}

# --- Paths ---
missing_paths <- required_paths[!file.exists(required_paths)]
if (length(missing_paths) > 0) {
  ok <- FALSE
  issues <- c(issues, paste0("Missing paths: ", paste(missing_paths, collapse = ", ")))
  message("Missing project paths:")
  for (p in missing_paths) message("  - ", p)
  message("  FAIL: run from EarlyT_Prong1 project root")
} else {
  message("Project paths: OK")
}

message("")
if (ok) {
  message("ENV READY: YES")
  quit(status = 0)
} else {
  message("ENV READY: NO")
  for (iss in issues) message("  - ", iss)
  quit(status = 1)
}
