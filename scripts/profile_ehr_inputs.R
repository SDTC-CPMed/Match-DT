#!/usr/bin/env Rscript
# Profile raw EHR tables before column mapping / ICD conversion.
#
# Usage:
#   Rscript --vanilla scripts/profile_ehr_inputs.R \
#     --participants data/raw/dummy_dirty/participants.csv \
#     --diagnoses data/raw/dummy_dirty/diagnoses.csv \
#     --write-icd-template data/raw/dummy_dirty/icd10_mapping.json

suppressPackageStartupMessages(library(optparse))

option_list <- list(
  make_option("--config", type = "character", default = NULL,
              help = "Optional config YAML to resolve default paths"),
  make_option("--participants", type = "character", default = NULL),
  make_option("--diagnoses", type = "character", default = NULL),
  make_option("--dictionary", type = "character", default = NULL),
  make_option("--participants-id-col", type = "character", default = NULL,
              help = "person id column in participants (auto-detect if omitted)"),
  make_option("--diagnoses-id-col", type = "character", default = NULL),
  make_option("--dx-col", type = "character", default = NULL,
              help = "diagnosis/code column (auto-detect if omitted)"),
  make_option("--write-icd-template", type = "character", default = NULL,
              help = "Write editable ICD mapping JSON scaffold for non-ICD values")
)

opt <- parse_args(
  OptionParser(
    usage = "Rscript --vanilla scripts/profile_ehr_inputs.R [options]",
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

root <- prong1_project_root()
if (!is.null(opt$config) || (is.null(opt$participants) && is.null(opt$diagnoses))) {
  cfg <- prong1_load_config(config_path = opt$config)
  p1 <- cfg$prong1
  if (is.null(opt$participants)) opt$participants <- p1$participants_file
  if (is.null(opt$diagnoses)) opt$diagnoses <- p1$diagnoses_file
  if (is.null(opt$dictionary)) opt$dictionary <- p1$disease_dictionary_file
}

participants_path <- prong1_resolve_path(opt$participants, root)
diagnoses_path <- prong1_resolve_path(opt$diagnoses, root)
dictionary_path <- prong1_resolve_path(opt$dictionary, root)

part <- prong1_read_table(participants_path)
diag <- prong1_read_table(diagnoses_path)

guess_id <- function(nms) {
  cand <- nms[grepl("id|uid|eid|person|patient|pt_id", nms, ignore.case = TRUE)]
  if (length(cand)) cand[[1]] else nms[[1]]
}
guess_dx <- function(nms) {
  cand <- nms[grepl("icd|dx|diag|code|condition", nms, ignore.case = TRUE)]
  if (length(cand)) cand[[1]] else {
    stop("Could not guess diagnosis column; pass --dx-col")
  }
}

pid_p <- if (!is.null(opt$participants_id_col)) opt$participants_id_col else guess_id(names(part))
pid_d <- if (!is.null(opt$diagnoses_id_col)) opt$diagnoses_id_col else guess_id(names(diag))
dx_col <- if (!is.null(opt$dx_col)) opt$dx_col else guess_dx(names(diag))

message("=== EHR input profile ===")
message("Participants: ", participants_path, " (n=", nrow(part), ")")
message("Diagnoses:    ", diagnoses_path, " (n=", nrow(diag), ")")
message("ID cols: participants$", pid_p, " / diagnoses$", pid_d, " | dx col: ", dx_col)

profile_cols <- function(df, label) {
  message("\n-- ", label, " columns --")
  for (nm in names(df)) {
    vals <- df[[nm]]
    nonempty <- vals[!is.na(vals) & nzchar(trimws(as.character(vals)))]
    samples <- utils::head(unique(as.character(nonempty)), 3)
    message("  ", nm, " | non-empty=", length(nonempty), " | samples: ",
            paste(samples, collapse = " | "))
  }
}
profile_cols(part, "participants")
profile_cols(diag, "diagnoses")

# Duplicates
ids <- as.character(part[[pid_p]])
n_dup <- sum(duplicated(ids))
message("\nDuplicate participant IDs: ", n_dup)
if (n_dup > 0) {
  other <- setdiff(names(part), pid_p)
  key <- if (length(other) > 0) {
    do.call(paste, c(part[other], sep = "\t"))
  } else {
    rep("", nrow(part))
  }
  conflict_n <- sum(tapply(key, ids, function(z) length(unique(z)) > 1))
  message("  IDs with conflicting non-ID fields: ", conflict_n)
}

orphans <- setdiff(as.character(diag[[pid_d]]), ids)
message("Orphan diagnosis person_ids: ", length(orphans))
if (length(orphans) > 0) {
  message("  Examples: ", paste(utils::head(orphans, 5), collapse = ", "))
}

# Low-cardinality
for (nm in names(part)) {
  u <- unique(na.omit(as.character(part[[nm]])))
  u <- u[nzchar(u)]
  if (length(u) > 0 && length(u) <= 20 &&
      grepl("sex|gender|centre|center|site|facility|ethn|race|ancestry", nm, ignore.case = TRUE)) {
    message("Unique ", nm, " (", length(u), "): ", paste(u, collapse = ", "))
  }
}

# Date formats
classify_date <- function(x) {
  x <- trimws(as.character(x))
  x <- x[!is.na(x) & nzchar(x) & !(tolower(x) %in% c("na", "nan", "null", "none"))]
  list(
    n = length(x),
    iso = sum(grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", x)),
    dmy = sum(grepl("^[0-9]{2}/[0-9]{2}/[0-9]{4}$", x)),
    ymd_slash = sum(grepl("^[0-9]{4}/[0-9]{2}/[0-9]{2}$", x)),
    other = sum(!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", x) &
                  !grepl("^[0-9]{2}/[0-9]{2}/[0-9]{4}$", x) &
                  !grepl("^[0-9]{4}/[0-9]{2}/[0-9]{2}$", x))
  )
}
message("\n-- Date-like columns --")
for (df_lab in list(list(part, "participants"), list(diag, "diagnoses"))) {
  df <- df_lab[[1]]
  lab <- df_lab[[2]]
  for (nm in names(df)) {
    if (!grepl("date|dt|time|dod|ltfu|enroll|visit|onset|baseline", nm, ignore.case = TRUE)) next
    st <- classify_date(df[[nm]])
    if (st$n == 0) next
    parsed <- prong1_parse_date(df[[nm]])
    rng <- range(parsed, na.rm = TRUE)
    message(
      "  ", lab, "$", nm, ": n=", st$n,
      " ISO=", st$iso, " DMY=", st$dmy, " YMD/=", st$ymd_slash, " other=", st$other,
      if (all(is.finite(as.numeric(rng)))) paste0(" range=", rng[1], "..", rng[2]) else ""
    )
  }
}

# Diagnosis code breakdown
dx <- trimws(as.character(diag[[dx_col]]))
dx <- dx[!is.na(dx) & nzchar(dx)]
valid3 <- grepl("^[A-Za-z][0-9]{2}$", dx)
dotted <- grepl("^[A-Za-z][0-9]{2}\\.[0-9A-Za-z]+$", dx)
non_icd <- !(valid3 | dotted)
message("\n-- Diagnosis code breakdown (", dx_col, ") --")
message("  valid level-3: ", sum(valid3))
message("  dotted ICD:    ", sum(dotted))
message("  non-ICD/other: ", sum(non_icd))

non_icd_vals <- dx[non_icd]
tab <- sort(table(non_icd_vals), decreasing = TRUE)
if (length(tab) > 0) {
  message("  Top non-ICD values:")
  for (i in seq_len(min(15L, length(tab)))) {
    message("    ", names(tab)[i], "  n=", as.integer(tab[i]))
  }
}

write_path <- opt$write_icd_template
if (is.null(write_path) && sum(non_icd) > 0) {
  message(
    "\nNon-ICD values detected. Suggest: --write-icd-template <path.json> ",
    "then fill icd10 / confirmed and run scripts/00b_map_diagnoses.R"
  )
}
if (!is.null(write_path) && nzchar(write_path)) {
  write_path <- prong1_resolve_path(write_path, root)
  dir.create(dirname(write_path), recursive = TRUE, showWarnings = FALSE)
  mappings <- lapply(names(tab), function(nm) {
    list(
      source_value = nm,
      n_rows = unname(as.integer(tab[[nm]])),
      icd10 = NULL,
      method = "unmapped",
      confidence = "unknown",
      notes = "Fill icd10 (level-3) or leave null to drop; set confirmed true after review.",
      confirmed = FALSE
    )
  })
  payload <- list(
    metadata = list(
      source_file = diagnoses_path,
      dx_col = dx_col,
      created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
    ),
    mappings = mappings
  )
  jsonlite::write_json(payload, write_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
  message("Wrote ICD mapping template: ", write_path, " (", length(mappings), " entries)")
}
