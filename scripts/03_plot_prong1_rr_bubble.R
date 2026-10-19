#!/usr/bin/env Rscript
# Plot log2(RR) vs mean directed lag years for significant trajectories.
#
# Usage (from project root):
#   Rscript --vanilla scripts/03_plot_prong1_rr_bubble.R

args <- commandArgs(trailingOnly = TRUE)

parse_args <- function(args) {
  out <- list(input = NULL, output_png = NULL, output_pdf = NULL)
  i <- 1L
  while (i <= length(args)) {
    key <- args[[i]]
    if (!startsWith(key, "--") || i == length(args)) stop("Unexpected argument: ", key)
    val <- args[[i + 1L]]
    if (key == "--input") out$input <- val
    else if (key == "--output-png") out$output_png <- val
    else if (key == "--output-pdf") out$output_pdf <- val
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
source(file.path("src", "prong1", "plot_bubble.R"))

cfg <- prong1_load_config()
root <- cfg$project_root
p1 <- cfg$prong1
plot_cfg <- cfg$plot

finals_path <- prong1_resolve_path(
  if (!is.null(cli$input)) cli$input else file.path(p1$output_dir, "Final_trajectories.csv"),
  root
)
output_png <- prong1_resolve_path(
  if (!is.null(cli$output_png)) cli$output_png else "reports/figures/prong1_rr_vs_years_bubble.png",
  root
)
output_pdf <- prong1_resolve_path(
  if (!is.null(cli$output_pdf)) cli$output_pdf else "reports/figures/prong1_rr_vs_years_bubble.pdf",
  root
)

prong1_plot_rr_bubble(
  finals_path = finals_path,
  output_png = output_png,
  output_pdf = output_pdf,
  width = if (is.null(plot_cfg$bubble_width)) 10 else plot_cfg$bubble_width,
  height = if (is.null(plot_cfg$bubble_height)) 7 else plot_cfg$bubble_height,
  dpi = if (is.null(plot_cfg$dpi)) 300 else plot_cfg$dpi
)
