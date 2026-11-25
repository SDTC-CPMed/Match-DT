# RR vs mean directed lag bubble plot for Match-DT finals.

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(ggrepel)
  library(readr)
})

# Map D1 ICD letter to trajectory category for coloring.
prong1_trajectory_type <- function(d1) {
  dplyr::case_when(
    grepl("^C", d1) ~ "Cancer-to-Cancer",
    grepl("^D", d1) ~ "Benign-to-Cancer",
    TRUE ~ "Non-Neoplastic-Disease-to-Cancer"
  )
}

#' Plot log2(RR) against mean D2-D1 lag years.
#'
#' @param finals_path Path to Final_trajectories.csv
#' @param output_png PNG path
#' @param output_pdf PDF path (optional)
#' @param width Figure width inches
#' @param height Figure height inches
#' @param dpi PNG resolution
prong1_plot_rr_bubble <- function(
    finals_path,
    output_png,
    output_pdf = NULL,
    width = 10,
    height = 7,
    dpi = 300
) {
  if (!file.exists(finals_path)) {
    stop("Final trajectories not found: ", finals_path,
         ". Run scripts/02_run_prong1_trajectories.R first.")
  }
  df <- readr::read_csv(finals_path, show_col_types = FALSE)
  if (nrow(df) == 0) {
    stop("Final_trajectories.csv is empty — no directed trajectories to plot.")
  }

  # "sans" is the device standard font (Helvetica in pdf()). Its encoding has
  # no arrow or unicode minus, so labels use ASCII "->" and "-".
  plot_df <- df %>%
    mutate(
      years = as.numeric(mean_lag_years_directed),
      log2_rr = log2(as.numeric(RR)),
      type = prong1_trajectory_type(D1),
      label = paste0(D1, "->", D2)
    ) %>%
    filter(is.finite(years), is.finite(log2_rr))

  if (nrow(plot_df) == 0) {
    stop("No finite years/RR rows available for plotting.")
  }

  # Colorblind-friendly palette by trajectory type.
  type_colors <- c(
    "Benign-to-Cancer" = "#0072B2",
    "Cancer-to-Cancer" = "#009E73",
    "Non-Neoplastic-Disease-to-Cancer" = "#E69F00"
  )

  # Bubble size encodes log2(RR); labels placed with ggrepel to reduce overlap.
  p <- ggplot(plot_df, aes(x = years, y = log2_rr, size = log2_rr, color = type, label = label)) +
    geom_point(alpha = 0.75) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "grey60") +
    geom_vline(xintercept = 0, linetype = "dotted", color = "grey60") +
    ggrepel::geom_text_repel(
      size = 3.2, max.overlaps = 20, family = "sans", show.legend = FALSE
    ) +
    scale_size_continuous(range = c(3, 12), guide = "none") +
    scale_color_manual(values = type_colors, drop = FALSE) +
    labs(
      x = "Mean time D2 - D1 (years)",
      y = "Relative risk (log2)",
      color = NULL,
      title = "Match-DT directed trajectories"
    ) +
    theme_classic(base_size = 12, base_family = "sans") +
    theme(panel.grid.minor = element_blank(), legend.position = "bottom")

  dir.create(dirname(output_png), recursive = TRUE, showWarnings = FALSE)
  ggsave(output_png, p, width = width, height = height, dpi = dpi)
  message("Wrote ", normalizePath(output_png))
  if (!is.null(output_pdf)) {
    ggsave(output_pdf, p, width = width, height = height)
    message("Wrote ", normalizePath(output_pdf))
  }
  invisible(p)
}
