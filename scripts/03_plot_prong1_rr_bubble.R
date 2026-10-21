#!/usr/bin/env Rscript
# Plot log2(RR) vs mean directed lag years for significant trajectories.
#
# Usage (from project root):
#   Rscript --vanilla scripts/03_plot_prong1_rr_bubble.R --help

suppressPackageStartupMessages(library(optparse))

# Optional CLI: --input, --output-png, --output-pdf.
option_list <- list(
  make_option("--input", type = "character", default = NULL,
              help = "Final_trajectories.csv (default: analysis output dir)"),
  make_option("--output-png", type = "character", default = NULL,
              help = "PNG path (default: reports/figures/prong1_rr_vs_years_bubble.png)"),
  make_option("--output-pdf", type = "character", default = NULL,
              help = "PDF path (default: reports/figures/prong1_rr_vs_years_bubble.pdf)")
)

# convert_hyphens_to_underscores: --output-png becomes opt$output_png.
opt <- parse_args(
  OptionParser(
    usage = "Rscript --vanilla scripts/03_plot_prong1_rr_bubble.R [options]",
    description = "Plot log2(RR) against mean directed lag years.",
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
source(file.path("src", "prong1", "plot_bubble.R"))

cfg <- prong1_load_config()
root <- cfg$project_root
p1 <- cfg$prong1
plot_cfg <- cfg$plot

# Defaults: Final_trajectories.csv from analysis output, figures under reports/.
finals_path <- prong1_resolve_path(
  if (!is.null(opt$input)) opt$input else file.path(p1$output_dir, "Final_trajectories.csv"),
  root
)
output_png <- prong1_resolve_path(
  if (!is.null(opt$output_png)) opt$output_png else "reports/figures/prong1_rr_vs_years_bubble.png",
  root
)
output_pdf <- prong1_resolve_path(
  if (!is.null(opt$output_pdf)) opt$output_pdf else "reports/figures/prong1_rr_vs_years_bubble.pdf",
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
