#!/usr/bin/env Rscript
# Apply an editable ICD-10 mapping JSON (or YAML/CSV) to a diagnoses table.
#
# Usage:
#   Rscript --vanilla scripts/00b_map_diagnoses.R \
#     --diagnoses data/raw/dummy_dirty/diagnoses.csv \
#     --dx-col dx_raw \
#     --lookup data/raw/dummy_dirty/icd10_mapping.json \
#     --output data/raw/dummy_dirty/diagnoses_mapped.csv

suppressPackageStartupMessages({
  library(optparse)
  library(readr)
  library(jsonlite)
  library(yaml)
})

option_list <- list(
  make_option("--diagnoses", type = "character", default = NULL),
  make_option("--dx-col", type = "character", default = "dx_raw"),
  make_option("--lookup", type = "character", default = NULL,
              help = "JSON (preferred), YAML, or CSV lookup"),
  make_option("--out-col", type = "character", default = "icd10_mapped"),
  make_option("--output", type = "character", default = NULL),
  make_option("--date-cols", type = "character", default = NULL,
              help = "Comma-separated date columns to normalize to ISO YYYY-MM-DD"),
  make_option("--require-confirmed", action = "store_true", default = FALSE,
              help = "Abort if any non-null matched mapping has confirmed: false")
)

opt <- parse_args(
  OptionParser(
    usage = "Rscript --vanilla scripts/00b_map_diagnoses.R [options]",
    option_list = option_list
  ),
  convert_hyphens_to_underscores = TRUE
)

if (is.null(opt$diagnoses) || is.null(opt$lookup) || is.null(opt$output)) {
  stop("Required: --diagnoses, --lookup, --output", call. = FALSE)
}

script_path <- local({
  ca <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", ca[startsWith(ca, "--file=")])
  if (length(f) == 1L && nzchar(f)) normalizePath(f) else NULL
})
if (!is.null(script_path)) {
  setwd(normalizePath(file.path(dirname(script_path), "..")))
}

source(file.path("src", "prong1", "prepare_input.R"))

root <- prong1_project_root()
diagnoses_path <- prong1_resolve_path(opt$diagnoses, root)
lookup_path <- prong1_resolve_path(opt$lookup, root)
output_path <- prong1_resolve_path(opt$output, root)

diag <- prong1_read_table(diagnoses_path)
if (!opt$dx_col %in% names(diag)) {
  stop("dx-col '", opt$dx_col, "' not in diagnoses. Columns: ", paste(names(diag), collapse = ", "))
}

# --- Load lookup ---
load_lookup <- function(path) {
  ext <- tolower(tools::file_ext(path))
  if (ext == "json") {
    obj <- jsonlite::fromJSON(path, simplifyVector = FALSE)
    if (!is.null(obj$mappings)) {
      rows <- lapply(obj$mappings, function(m) {
        data.frame(
          source_value = as.character(m$source_value %||% NA),
          icd10 = if (is.null(m$icd10)) NA_character_ else as.character(m$icd10),
          method = as.character(m$method %||% NA_character_),
          confirmed = isTRUE(m$confirmed),
          n_rows = as.integer(m$n_rows %||% NA_integer_),
          stringsAsFactors = FALSE
        )
      })
      return(list(df = bind_rows_safe(rows), flat = FALSE, path = path))
    }
    # Flat object
    nms <- names(obj)
    df <- data.frame(
      source_value = nms,
      icd10 = vapply(nms, function(nm) {
        v <- obj[[nm]]
        if (is.null(v)) NA_character_ else as.character(v)
      }, character(1)),
      method = "flat_dict",
      confirmed = FALSE,
      n_rows = NA_integer_,
      stringsAsFactors = FALSE
    )
    message("WARNING: flat JSON dictionary loaded; all entries treated as confirmed: false.")
    return(list(df = df, flat = TRUE, path = path))
  }
  if (ext %in% c("yml", "yaml")) {
    obj <- yaml::read_yaml(path)
    if (!is.null(obj$mappings)) {
      # same as JSON mappings list of named lists
      rows <- lapply(obj$mappings, function(m) {
        data.frame(
          source_value = as.character(m$source_value),
          icd10 = if (is.null(m$icd10)) NA_character_ else as.character(m$icd10),
          method = as.character(m$method %||% NA_character_),
          confirmed = isTRUE(m$confirmed),
          n_rows = as.integer(m$n_rows %||% NA_integer_),
          stringsAsFactors = FALSE
        )
      })
      return(list(df = bind_rows_safe(rows), flat = FALSE, path = path))
    }
    df <- data.frame(
      source_value = names(obj),
      icd10 = unlist(obj, use.names = FALSE),
      method = "yaml_flat",
      confirmed = FALSE,
      n_rows = NA_integer_,
      stringsAsFactors = FALSE
    )
    return(list(df = df, flat = TRUE, path = path))
  }
  # CSV: source_value, icd10, confirmed optional
  csv <- readr::read_csv(path, col_types = readr::cols(.default = readr::col_character()))
  if (!all(c("source_value", "icd10") %in% names(csv))) {
    stop("CSV lookup needs source_value and icd10 columns")
  }
  conf <- if ("confirmed" %in% names(csv)) {
    tolower(csv$confirmed) %in% c("true", "1", "yes")
  } else {
    rep(FALSE, nrow(csv))
  }
  df <- data.frame(
    source_value = csv$source_value,
    icd10 = ifelse(csv$icd10 == "", NA_character_, csv$icd10),
    method = if ("method" %in% names(csv)) csv$method else "csv",
    confirmed = conf,
    n_rows = NA_integer_,
    stringsAsFactors = FALSE
  )
  list(df = df, flat = !("confirmed" %in% names(csv)), path = path)
}

bind_rows_safe <- function(rows) {
  if (length(rows) == 0) {
    return(data.frame(
      source_value = character(), icd10 = character(), method = character(),
      confirmed = logical(), n_rows = integer(), stringsAsFactors = FALSE
    ))
  }
  do.call(rbind, rows)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

lk <- load_lookup(lookup_path)
lookup_df <- lk$df
lookup_df$key <- tolower(trimws(lookup_df$source_value))

# Validate target ICDs in lookup
has_code <- !is.na(lookup_df$icd10) & nzchar(lookup_df$icd10)
ok_code <- grepl("^[A-Za-z][0-9]{2}", toupper(gsub("[^A-Za-z0-9]", "", lookup_df$icd10)))
bad_targets <- lookup_df[has_code & !ok_code, , drop = FALSE]
if (nrow(bad_targets) > 0) {
  stop(
    "Invalid icd10 targets in lookup (must be letter+2 digits after normalize):\n  ",
    paste(bad_targets$source_value, "→", bad_targets$icd10, collapse = "\n  "),
    call. = FALSE
  )
}

# Normalize valid targets to level-3
lookup_df$icd10_norm <- prong1_normalize_icd10_level3(lookup_df$icd10)

raw <- as.character(diag[[opt$dx_col]])
key <- tolower(trimws(raw))
mapped <- lookup_df$icd10_norm[match(key, lookup_df$key)]
confirmed_hit <- lookup_df$confirmed[match(key, lookup_df$key)]
in_lookup <- !is.na(match(key, lookup_df$key))

already_icd <- prong1_looks_like_icd10(raw)
already_norm <- prong1_normalize_icd10_level3(raw)

out_icd <- rep(NA_character_, length(raw))
# Prefer lookup when present
out_icd[in_lookup] <- mapped[in_lookup]
# Else if already ICD-shaped, normalize
use_existing <- !in_lookup & already_icd
out_icd[use_existing] <- already_norm[use_existing]

# Counts
n_already <- sum(use_existing & !is.na(out_icd))
n_mapped_conf <- sum(in_lookup & !is.na(mapped) & confirmed_hit %in% TRUE)
n_mapped_unconf <- sum(in_lookup & !is.na(mapped) & !confirmed_hit %in% TRUE)
n_null_drop <- sum(in_lookup & is.na(mapped))
n_unmapped <- sum(!in_lookup & !already_icd & !is.na(raw) & nzchar(trimws(raw)))

diag[[opt$out_col]] <- out_icd

# Optional date normalization
if (!is.null(opt$date_cols) && nzchar(opt$date_cols)) {
  dcols <- trimws(strsplit(opt$date_cols, ",")[[1]])
  for (dc in dcols) {
    if (!dc %in% names(diag)) {
      warning("date-col not found: ", dc)
      next
    }
    parsed <- prong1_parse_date(diag[[dc]])
    diag[[dc]] <- ifelse(is.na(parsed), as.character(diag[[dc]]), format(parsed, "%Y-%m-%d"))
  }
}

dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
readr::write_csv(diag, output_path)

message("Mapped diagnoses written: ", output_path)
message("  already_valid_icd10:     ", n_already)
message("  mapped_confirmed:        ", n_mapped_conf)
message("  mapped_unconfirmed:      ", n_mapped_unconf)
message("  intentionally_dropped:   ", n_null_drop)
message("  unmapped_not_in_lookup:  ", n_unmapped)

if (n_mapped_unconf > 0 || n_unmapped > 0) {
  unconf_rows <- lookup_df[!lookup_df$confirmed & !is.na(lookup_df$icd10_norm), , drop = FALSE]
  message("\n========== HUMAN REVIEW REQUIRED ==========")
  message("Review/edit the mapping file before trusting downstream results:")
  message("  ", lookup_path)
  if (nrow(unconf_rows) > 0) {
    message("Unconfirmed mappings (source → ICD):")
    for (i in seq_len(min(20L, nrow(unconf_rows)))) {
      message("  - ", unconf_rows$source_value[i], " → ", unconf_rows$icd10_norm[i],
              if (!is.na(unconf_rows$n_rows[i])) paste0(" (n_rows=", unconf_rows$n_rows[i], ")") else "")
    }
  }
  if (n_unmapped > 0) {
    message("Unmapped non-ICD values remain (", n_unmapped, " rows); they will be dropped in 01.")
  }
  message("Set \"confirmed\": true in JSON after human review, or pass --require-confirmed.")
  message("===========================================\n")
}

if (isTRUE(opt$require_confirmed) && n_mapped_unconf > 0) {
  message("ERROR: --require-confirmed set but mapped_unconfirmed=", n_mapped_unconf)
  quit(status = 1)
}
