# Prong 1 generic EHR input preparation helpers.
# Canonical schema: participants + long diagnoses (+ optional disease dictionary).

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(yaml)
  library(jsonlite)
  library(stringr)
})

.prong1_age_band_levels <- c("20-", "20-29", "30-39", "40-49", "50-59", "60-69", "70+")

# Walk up from cwd until config/config.yaml is found (project root marker).
prong1_project_root <- function(start = getwd()) {
  path <- normalizePath(start, mustWork = TRUE)
  for (i in seq_len(12)) {
    if (file.exists(file.path(path, "config", "config.yaml"))) {
      return(path)
    }
    parent <- dirname(path)
    if (identical(parent, path)) break
    path <- parent
  }
  stop("Could not locate project root (missing config/config.yaml).")
}

# Load YAML config; optional explicit path for --config.
prong1_load_config <- function(project_root = NULL, config_path = NULL) {
  if (is.null(project_root)) project_root <- prong1_project_root()
  cfg_path <- if (!is.null(config_path) && nzchar(config_path)) {
    if (grepl("^(/|[A-Za-z]:)", config_path)) config_path else file.path(project_root, config_path)
  } else {
    file.path(project_root, "config", "config.yaml")
  }
  if (!file.exists(cfg_path)) {
    stop("Config file not found: ", cfg_path)
  }
  cfg <- yaml::read_yaml(cfg_path)
  if (is.null(cfg$prong1)) {
    stop("config.yaml is missing a 'prong1:' section: ", cfg_path)
  }
  cfg$project_root <- project_root
  cfg$config_path <- cfg_path
  cfg
}

# Absolute paths pass through; relative paths are joined to project_root.
prong1_resolve_path <- function(path, project_root) {
  if (is.null(path) || !nzchar(path)) return(NULL)
  if (grepl("^(/|[A-Za-z]:)", path)) return(path)
  file.path(project_root, path)
}

# Canonical ← source column map. Missing/empty map_path → identity defaults.
# Non-empty path that does not exist → hard error (no silent fallback).
prong1_load_column_map <- function(map_path) {
  default_map <- list(
    participants = list(
      person_id = "person_id",
      sex = "sex",
      age_at_baseline = "age_at_baseline",
      baseline_date = "baseline_date",
      assessment_centre = "assessment_centre",
      ethnicity = "ethnicity",
      death_date = "death_date",
      lost_to_followup_date = "lost_to_followup_date"
    ),
    diagnoses = list(
      person_id = "person_id",
      icd10 = "icd10",
      diagnosis_date = "diagnosis_date"
    ),
    disease_dictionary = list(
      icd10 = "icd10",
      disease_name = "disease_name"
    )
  )
  if (is.null(map_path) || !nzchar(as.character(map_path)[[1]])) {
    return(default_map)
  }
  if (!file.exists(map_path)) {
    stop(
      "Column-map file not found: ", map_path,
      "\nProvide a valid YAML path or omit --column-map / column_map_file to use canonical column names."
    )
  }
  user_map <- yaml::read_yaml(map_path)
  for (section in names(default_map)) {
    if (!is.null(user_map[[section]])) {
      for (nm in names(default_map[[section]])) {
        if (!is.null(user_map[[section]][[nm]]) && nzchar(user_map[[section]][[nm]])) {
          default_map[[section]][[nm]] <- user_map[[section]][[nm]]
        }
      }
    }
  }
  default_map
}

# Read CSV / TSV / RDS into a plain data.frame (all character for CSV/TSV).
prong1_read_table <- function(path) {
  if (is.null(path) || !file.exists(path)) {
    stop("Input file not found: ", path)
  }
  ext <- tolower(tools::file_ext(path))
  if (ext == "rds") {
    return(as.data.frame(readRDS(path), stringsAsFactors = FALSE))
  }
  col_chr <- readr::cols(.default = readr::col_character())
  if (ext %in% c("tsv", "txt")) {
    return(as.data.frame(
      readr::read_tsv(path, col_types = col_chr, show_col_types = FALSE),
      stringsAsFactors = FALSE
    ))
  }
  as.data.frame(
    readr::read_csv(path, col_types = col_chr, show_col_types = FALSE),
    stringsAsFactors = FALSE
  )
}

# Select mapped source columns and rename them to canonical names.
prong1_rename_mapped <- function(df, mapping, table_name = "table") {
  expected <- unlist(mapping, use.names = FALSE)
  missing <- setdiff(expected, names(df))
  if (length(missing) > 0) {
    hint <- ""
    if (ncol(df) == 1L) {
      hint <- paste0(
        "\nOnly 1 column was parsed (", names(df)[[1]], "). ",
        "If the file is semicolon-delimited, convert to CSV/TSV or re-export with commas."
      )
    }
    stop(
      "Missing mapped columns for '", table_name, "'.\n",
      "  Expected source columns: ", paste(expected, collapse = ", "), "\n",
      "  Missing: ", paste(missing, collapse = ", "), "\n",
      "  Found headers (", length(names(df)), "): ",
      paste(names(df), collapse = ", "),
      hint,
      call. = FALSE
    )
  }
  out <- df[, expected, drop = FALSE]
  names(out) <- names(mapping)
  out
}

# Explicit format matching — never let base::as.Date guess from the first cell.
prong1_parse_date <- function(x) {
  if (inherits(x, "Date")) return(x)
  if (inherits(x, "POSIXt")) return(as.Date(x))
  x_chr <- trimws(as.character(x))
  x_chr[x_chr == "" | tolower(x_chr) %in% c("na", "nan", "null", "none")] <- NA_character_
  parsed <- rep(as.Date(NA), length(x_chr))
  iso <- !is.na(x_chr) & grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", x_chr)
  dmy <- !is.na(x_chr) & grepl("^[0-9]{2}/[0-9]{2}/[0-9]{4}$", x_chr)
  ymd_slash <- !is.na(x_chr) & grepl("^[0-9]{4}/[0-9]{2}/[0-9]{2}$", x_chr)
  if (any(iso)) {
    parsed[iso] <- as.Date(x_chr[iso], format = "%Y-%m-%d")
  }
  if (any(dmy)) {
    parsed[dmy] <- as.Date(x_chr[dmy], format = "%d/%m/%Y")
  }
  if (any(ymd_slash)) {
    parsed[ymd_slash] <- as.Date(x_chr[ymd_slash], format = "%Y/%m/%d")
  }
  parsed
}

prong1_sample_values <- function(x, n = 5L) {
  x <- as.character(x)
  x <- x[!is.na(x) & nzchar(x)]
  if (length(x) == 0) return("(none)")
  paste(utils::head(unique(x), n), collapse = "; ")
}

prong1_warn_date_qc <- function(label, raw_chr, parsed, baseline = NULL) {
  raw_chr <- trimws(as.character(raw_chr))
  nonempty <- !is.na(raw_chr) & nzchar(raw_chr) &
    !(tolower(raw_chr) %in% c("na", "nan", "null", "none"))
  n_fail <- sum(nonempty & is.na(parsed))
  if (n_fail > 0) {
    samples <- prong1_sample_values(raw_chr[nonempty & is.na(parsed)])
    message("  WARNING [", label, "]: ", n_fail, " unparseable date(s). Examples: ", samples)
  }
  ok <- !is.na(parsed)
  implausible <- ok & (parsed < as.Date("1900-01-01") | parsed > Sys.Date())
  n_impl <- sum(implausible)
  if (n_impl > 0) {
    message(
      "  WARNING [", label, "]: ", n_impl,
      " implausible date(s) (< 1900-01-01 or > today). Examples: ",
      prong1_sample_values(format(parsed[implausible]))
    )
  }
  n_before_baseline <- 0L
  if (!is.null(baseline)) {
    bad_order <- ok & !is.na(baseline) & parsed < baseline
    n_before_baseline <- sum(bad_order)
    if (n_before_baseline > 0) {
      message(
        "  WARNING [", label, "]: ", n_before_baseline,
        " date(s) earlier than baseline_date."
      )
    }
  }
  list(
    n_unparseable = as.integer(n_fail),
    n_implausible = as.integer(n_impl),
    n_before_baseline = as.integer(n_before_baseline)
  )
}

# Collapse common sex encodings (M/F, 0/1, male/female, …) to male/female.
prong1_normalize_sex <- function(x) {
  s <- tolower(trimws(as.character(x)))
  out <- rep(NA_character_, length(s))
  out[s %in% c("male", "m", "1", "man")] <- "male"
  out[s %in% c("female", "f", "0", "woman")] <- "female"
  out
}

# ICD-10 level-3: letter + two digits after stripping non-alphanumerics.
# Invalid free text / junk → NA (never PEN/NOT/ESS truncations).
prong1_normalize_icd10_level3 <- function(x) {
  cleaned <- toupper(gsub("[^A-Za-z0-9]", "", as.character(x)))
  ok <- grepl("^[A-Z][0-9]{2}", cleaned)
  out <- rep(NA_character_, length(cleaned))
  out[ok] <- substr(cleaned[ok], 1L, 3L)
  out
}

prong1_looks_like_icd10 <- function(x) {
  x <- trimws(as.character(x))
  grepl("^[A-Za-z][0-9]{2}(\\.[0-9A-Za-z]+)?$", x)
}

# Decade age bands used for matching covariates.
prong1_age_band <- function(age) {
  dplyr::case_when(
    is.na(age) ~ NA_character_,
    age < 20 ~ "20-",
    age < 30 ~ "20-29",
    age < 40 ~ "30-39",
    age < 50 ~ "40-49",
    age < 60 ~ "50-59",
    age < 70 ~ "60-69",
    TRUE ~ "70+"
  )
}

prong1_age_band_factor <- function(age_or_band) {
  vals <- if (is.numeric(age_or_band)) {
    prong1_age_band(age_or_band)
  } else {
    as.character(age_or_band)
  }
  factor(vals, levels = .prong1_age_band_levels)
}

# Make disease labels filesystem- and TSV-friendly.
prong1_sanitize_disease_name <- function(x) {
  x <- gsub("[ ,/&]", "_", as.character(x))
  x <- gsub("[()'\\.;]", "", x)
  x <- gsub("_+", "_", x)
  x
}

# Load ICD mapping JSON metadata (optional QC for unconfirmed mappings).
prong1_load_icd_map_json <- function(path) {
  if (is.null(path) || !nzchar(path) || !file.exists(path)) return(NULL)
  obj <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  if (is.null(obj$mappings) && is.list(obj) && is.null(obj$metadata)) {
    # Flat dict {"label": "I10"}
    mappings <- lapply(names(obj), function(nm) {
      list(
        source_value = nm,
        icd10 = obj[[nm]],
        confirmed = FALSE,
        method = "flat_dict"
      )
    })
    return(list(metadata = list(), mappings = mappings, flat = TRUE))
  }
  list(metadata = obj$metadata %||% list(), mappings = obj$mappings %||% list(), flat = FALSE)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

#' Prepare Prong 1 analysis-ready tables from generic EHR inputs.
#'
#' @return list(participants, diagnoses, disease_n_patient, report)
prong1_prepare_input <- function(
    participants_path,
    diagnoses_path,
    dictionary_path = NULL,
    column_map_path = NULL,
    n_patient_min = 100L,
    output_dir = NULL,
    icd_map_json = NULL
) {
  col_map <- prong1_load_column_map(column_map_path)

  participants_raw <- prong1_read_table(participants_path)
  diagnoses_raw <- prong1_read_table(diagnoses_path)

  n_part_in <- nrow(participants_raw)
  n_diag_in <- nrow(diagnoses_raw)

  participants <- prong1_rename_mapped(
    participants_raw, col_map$participants, table_name = "participants"
  )
  diagnoses <- prong1_rename_mapped(
    diagnoses_raw, col_map$diagnoses, table_name = "diagnoses"
  )

  # Preserve raw strings for QC samples before normalization.
  sex_raw <- as.character(participants$sex)
  baseline_raw <- as.character(participants$baseline_date)
  death_raw <- as.character(participants$death_date)
  ltfu_raw <- as.character(participants$lost_to_followup_date)
  icd_raw <- as.character(diagnoses$icd10)
  diag_date_raw <- as.character(diagnoses$diagnosis_date)

  # Detect free-text / non-ICD before normalization.
  icd_nonempty <- !is.na(icd_raw) & nzchar(trimws(icd_raw))
  looks_icd <- prong1_looks_like_icd10(icd_raw)
  n_non_icd_raw <- sum(icd_nonempty & !looks_icd)
  non_icd_examples <- prong1_sample_values(icd_raw[icd_nonempty & !looks_icd])
  if (n_non_icd_raw > 0) {
    message(
      "DIAGNOSTIC: ", n_non_icd_raw, " / ", sum(icd_nonempty),
      " diagnosis values do not look like ICD-10 (spaces or not letter+2 digits).\n",
      "  Examples: ", non_icd_examples, "\n",
      "  Generate/review an ICD-10 mapping JSON with scripts/profile_ehr_inputs.R ",
      "(--write-icd-template) and scripts/00b_map_diagnoses.R before relying on prep."
    )
  }

  participants <- participants %>%
    mutate(
      person_id = as.character(person_id),
      sex = prong1_normalize_sex(sex),
      age_at_baseline = suppressWarnings(as.numeric(age_at_baseline)),
      baseline_date = prong1_parse_date(baseline_date),
      assessment_centre = as.character(assessment_centre),
      ethnicity = as.character(ethnicity),
      death_date = prong1_parse_date(death_date),
      lost_to_followup_date = prong1_parse_date(lost_to_followup_date)
    )

  message("Date QC:")
  qc_baseline <- prong1_warn_date_qc("baseline_date", baseline_raw, participants$baseline_date)
  qc_death <- prong1_warn_date_qc(
    "death_date", death_raw, participants$death_date, participants$baseline_date
  )
  qc_ltfu <- prong1_warn_date_qc(
    "lost_to_followup_date", ltfu_raw, participants$lost_to_followup_date, participants$baseline_date
  )

  # Duplicate person_id conflict check before collapse.
  n_dup_id <- sum(duplicated(participants$person_id))
  if (n_dup_id > 0) {
    core_cols <- c("sex", "age_at_baseline", "baseline_date", "assessment_centre", "ethnicity")
    dup_df <- participants[participants$person_id %in% participants$person_id[duplicated(participants$person_id)], , drop = FALSE]
    conflict_ids <- character(0)
    for (pid in unique(dup_df$person_id)) {
      sub <- dup_df[dup_df$person_id == pid, core_cols, drop = FALSE]
      if (any(vapply(sub, function(col) length(unique(as.character(col))) > 1, logical(1)))) {
        conflict_ids <- c(conflict_ids, pid)
      }
    }
    if (length(conflict_ids) > 0) {
      message(
        "  WARNING: ", length(conflict_ids),
        " duplicate person_id(s) disagree on core fields before dedup. Examples: ",
        prong1_sample_values(conflict_ids)
      )
    }
  }
  participants <- participants %>% filter(!duplicated(person_id))

  # Sex drop samples from raw that failed normalization (on deduped set index — recompute).
  drop_sex <- sum(is.na(participants$sex))
  sex_nonempty <- !is.na(sex_raw) & nzchar(trimws(sex_raw))
  sex_bad_samples <- prong1_sample_values(
    sex_raw[sex_nonempty & is.na(prong1_normalize_sex(sex_raw))]
  )

  drop_age <- sum(is.na(participants$age_at_baseline))
  drop_baseline <- sum(is.na(participants$baseline_date))
  drop_centre <- sum(is.na(participants$assessment_centre) | participants$assessment_centre == "")
  drop_eth <- sum(is.na(participants$ethnicity) | participants$ethnicity == "")

  participants <- participants %>%
    filter(
      !is.na(sex),
      !is.na(age_at_baseline),
      !is.na(baseline_date),
      !is.na(assessment_centre), assessment_centre != "",
      !is.na(ethnicity), ethnicity != ""
    ) %>%
    mutate(
      assessment_year = as.numeric(format(baseline_date, "%Y")),
      age_band = prong1_age_band_factor(age_at_baseline),
      sex = factor(sex, levels = c("female", "male")),
      assessment_centre = as.factor(assessment_centre),
      ethnicity = as.factor(ethnicity)
    )

  # Diagnoses QC on raw before drop.
  qc_diag_date <- prong1_warn_date_qc("diagnosis_date", diag_date_raw, prong1_parse_date(diag_date_raw))

  diagnoses <- diagnoses %>%
    mutate(
      person_id = as.character(person_id),
      icd10_raw = as.character(icd10),
      icd10 = prong1_normalize_icd10_level3(icd10),
      diagnosis_date = prong1_parse_date(diagnosis_date)
    )

  n_diag_bad_icd <- sum(is.na(diagnoses$icd10))
  bad_icd_samples <- prong1_sample_values(diagnoses$icd10_raw[is.na(diagnoses$icd10)])
  n_diag_bad_date <- sum(is.na(diagnoses$diagnosis_date))
  bad_date_samples <- prong1_sample_values(diag_date_raw[is.na(prong1_parse_date(diag_date_raw))])

  share_bad_icd <- if (n_diag_in > 0) n_diag_bad_icd / n_diag_in else 1
  if (n_non_icd_raw > 0 || share_bad_icd >= 0.5) {
    message(
      "  WARNING: bad/non-ICD diagnoses: dropped=", n_diag_bad_icd,
      " (", round(100 * share_bad_icd, 1), "%). Examples: ", bad_icd_samples
    )
  }

  diagnoses <- diagnoses %>% filter(!is.na(icd10), !is.na(diagnosis_date))

  n_diag_orphans <- sum(!(diagnoses$person_id %in% participants$person_id))
  if (n_diag_orphans > 0) {
    message(
      "  WARNING: ", n_diag_orphans,
      " diagnosis row(s) orphaned (person_id not in cleaned participants). ",
      "Check ID formatting (e.g. P00001 vs 1). Examples: ",
      prong1_sample_values(diagnoses$person_id[!(diagnoses$person_id %in% participants$person_id)])
    )
  }
  diagnoses <- diagnoses %>% filter(person_id %in% participants$person_id)

  if (nrow(diagnoses) == 0) {
    diagnoses_earliest <- diagnoses[, c("person_id", "icd10", "diagnosis_date"), drop = FALSE]
  } else {
    diagnoses_earliest <- diagnoses %>%
      group_by(person_id, icd10) %>%
      summarise(diagnosis_date = min(diagnosis_date, na.rm = TRUE), .groups = "drop")
  }

  dictionary <- NULL
  if (!is.null(dictionary_path) && nzchar(dictionary_path) && file.exists(dictionary_path) &&
      nrow(diagnoses_earliest) > 0) {
    dictionary_raw <- prong1_read_table(dictionary_path)
    dictionary <- tryCatch(
      prong1_rename_mapped(
        dictionary_raw, col_map$disease_dictionary, table_name = "disease_dictionary"
      ),
      error = function(e) {
        message("  WARNING: skipping disease_dictionary — ", conditionMessage(e))
        NULL
      }
    )
    if (!is.null(dictionary)) {
      dictionary <- dictionary %>%
        mutate(
          icd10 = prong1_normalize_icd10_level3(icd10),
          disease_name = prong1_sanitize_disease_name(disease_name)
        ) %>%
        filter(!is.na(icd10), !is.na(disease_name), disease_name != "") %>%
        distinct(icd10, .keep_all = TRUE)
    }
  }

  disease_n_patient <- diagnoses_earliest %>%
    count(icd10, name = "n_patients") %>%
    mutate(disease_name = icd10)

  if (!is.null(dictionary)) {
    disease_n_patient <- disease_n_patient %>%
      left_join(
        dictionary %>% transmute(icd10, disease_name_dict = disease_name),
        by = "icd10"
      ) %>%
      mutate(disease_name = ifelse(!is.na(disease_name_dict), disease_name_dict, disease_name)) %>%
      select(icd10, disease_name, n_patients)
    n_dict_cover <- sum(disease_n_patient$icd10 %in% dictionary$icd10)
    if (n_dict_cover < nrow(disease_n_patient)) {
      message(
        "  WARNING: disease_dictionary covers ", n_dict_cover, "/",
        nrow(disease_n_patient), " detected codes."
      )
    }
  }

  n_diseases_ge_min <- sum(disease_n_patient$n_patients >= n_patient_min)

  # Unconfirmed ICD map JSON warning.
  n_unconfirmed_map <- 0L
  unconfirmed_examples <- character(0)
  icd_map_info <- prong1_load_icd_map_json(icd_map_json)
  if (!is.null(icd_map_info)) {
    for (m in icd_map_info$mappings) {
      conf <- isTRUE(m$confirmed)
      icd <- m$icd10
      if (!conf && !is.null(icd) && !identical(icd, NULL) && nzchar(as.character(icd))) {
        n_unconfirmed_map <- n_unconfirmed_map + 1L
        unconfirmed_examples <- c(
          unconfirmed_examples,
          paste0(m$source_value %||% "?", "→", icd)
        )
      }
    }
    if (isTRUE(icd_map_info$flat)) {
      message(
        "  WARNING: flat ICD map JSON treated all entries as confirmed: false. ",
        "Review and use the full mappings schema with confirmed: true."
      )
      n_unconfirmed_map <- max(n_unconfirmed_map, length(icd_map_info$mappings))
    }
    if (n_unconfirmed_map > 0) {
      message(
        "\n========== HUMAN REVIEW REQUIRED ==========\n",
        "  ", n_unconfirmed_map, " ICD mapping(s) are confirmed: false.\n",
        "  Examples: ", paste(utils::head(unique(unconfirmed_examples), 8), collapse = "; "), "\n",
        "  Edit ", icd_map_json, " then re-run 00b / 01 if codes need correction.\n",
        "===========================================\n"
      )
    }
  }

  ready <- nrow(participants) >= 1 && nrow(diagnoses_earliest) >= 1
  # Fail READY if essentially all diagnoses were non-ICD / dropped.
  if (n_diag_in > 0 && nrow(diagnoses_earliest) < 1) {
    ready <- FALSE
  }
  if (n_diag_in > 0 && share_bad_icd >= 0.95 && nrow(diagnoses_earliest) < max(1, 0.05 * n_diag_in)) {
    ready <- FALSE
  }

  report <- list(
    n_participants_in = n_part_in,
    n_participants_out = nrow(participants),
    n_duplicate_person_id_dropped = n_dup_id,
    n_dropped_invalid_sex = drop_sex,
    n_dropped_missing_age = drop_age,
    n_dropped_missing_baseline_date = drop_baseline,
    n_dropped_missing_centre = drop_centre,
    n_dropped_missing_ethnicity = drop_eth,
    n_diagnoses_in = n_diag_in,
    n_diagnoses_earliest_out = nrow(diagnoses_earliest),
    n_diag_dropped_bad_icd = n_diag_bad_icd,
    n_diag_dropped_bad_date = n_diag_bad_date,
    n_diag_dropped_orphan_person = n_diag_orphans,
    n_death_date_unparseable = qc_death$n_unparseable,
    n_ltfu_date_unparseable = qc_ltfu$n_unparseable,
    n_baseline_date_unparseable = qc_baseline$n_unparseable,
    n_diagnosis_date_unparseable = qc_diag_date$n_unparseable,
    n_death_before_baseline = qc_death$n_before_baseline,
    n_ltfu_before_baseline = qc_ltfu$n_before_baseline,
    n_non_icd_looking_raw = as.integer(n_non_icd_raw),
    n_unconfirmed_icd_mappings = n_unconfirmed_map,
    samples = list(
      invalid_sex = sex_bad_samples,
      bad_icd = bad_icd_samples,
      bad_diagnosis_date = bad_date_samples,
      non_icd_raw = non_icd_examples
    ),
    n_diseases = nrow(disease_n_patient),
    n_diseases_ge_n_patient_min = n_diseases_ge_min,
    n_patient_min = n_patient_min,
    ready = ready
  )

  if (!is.null(output_dir)) {
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
    saveRDS(participants, file.path(output_dir, "participants.rds"))
    saveRDS(diagnoses_earliest, file.path(output_dir, "diagnoses_earliest.rds"))
    readr::write_csv(participants, file.path(output_dir, "participants.csv"))
    readr::write_csv(diagnoses_earliest, file.path(output_dir, "diagnoses_earliest.csv"))
    readr::write_tsv(disease_n_patient, file.path(output_dir, "disease_n_patient.tsv"))
    jsonlite::write_json(report, file.path(output_dir, "prep_report.json"), pretty = TRUE, auto_unbox = TRUE)
  }

  list(
    participants = participants,
    diagnoses = diagnoses_earliest,
    disease_n_patient = disease_n_patient,
    report = report
  )
}

# Console checklist so the next pipeline step is obvious.
prong1_print_prep_checklist <- function(report, output_dir) {
  message("Prong 1 prep checklist")
  message("  participants: ", report$n_participants_in, " -> ", report$n_participants_out)
  message("  diagnoses (earliest person x ICD): ", report$n_diagnoses_earliest_out)
  message("  diseases: ", report$n_diseases,
          " (n >= ", report$n_patient_min, ": ", report$n_diseases_ge_n_patient_min, ")")

  drop_fields <- c(
    "n_duplicate_person_id_dropped",
    "n_dropped_invalid_sex",
    "n_dropped_missing_age",
    "n_dropped_missing_baseline_date",
    "n_dropped_missing_centre",
    "n_dropped_missing_ethnicity",
    "n_diag_dropped_bad_icd",
    "n_diag_dropped_bad_date",
    "n_diag_dropped_orphan_person",
    "n_death_date_unparseable",
    "n_ltfu_date_unparseable",
    "n_baseline_date_unparseable",
    "n_diagnosis_date_unparseable"
  )
  message("  Drop / parse counters:")
  for (f in drop_fields) {
    v <- report[[f]]
    if (!is.null(v) && is.numeric(v) && v > 0) {
      extra <- ""
      if (identical(f, "n_dropped_invalid_sex") && !is.null(report$samples$invalid_sex)) {
        extra <- paste0(" | examples: ", report$samples$invalid_sex)
      }
      if (identical(f, "n_diag_dropped_bad_icd") && !is.null(report$samples$bad_icd)) {
        extra <- paste0(" | examples: ", report$samples$bad_icd)
      }
      if (identical(f, "n_diag_dropped_bad_date") && !is.null(report$samples$bad_diagnosis_date)) {
        extra <- paste0(" | examples: ", report$samples$bad_diagnosis_date)
      }
      message("    ", f, ": ", v, extra)
    }
  }
  if (!is.null(report$n_unconfirmed_icd_mappings) && report$n_unconfirmed_icd_mappings > 0) {
    message(
      "  UNCONFIRMED ICD mappings in use: ", report$n_unconfirmed_icd_mappings,
      " — human review required (see icd map JSON)."
    )
  }

  message("  outputs: ", output_dir)
  ready <- isTRUE(report$ready)
  if (!ready || report$n_participants_out < 1 || report$n_diagnoses_earliest_out < 1) {
    message("  READY: NO — fix drops / ICD mapping / column map, then re-run 01")
    if (!is.null(report$n_non_icd_looking_raw) && report$n_non_icd_looking_raw > 0) {
      message(
        "  Hint: ", report$n_non_icd_looking_raw,
        " raw diagnosis values were not ICD-like. Use profile_ehr_inputs.R + 00b_map_diagnoses.R."
      )
    }
  } else {
    message("  READY: YES — run scripts/02_run_prong1_trajectories.R next")
  }
  invisible(ready)
}
