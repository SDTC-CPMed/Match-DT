# Prong 1 generic EHR input preparation helpers.
# Canonical schema: participants + long diagnoses (+ optional disease dictionary).

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(yaml)
  library(jsonlite)
  library(stringr)
})

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

prong1_load_config <- function(project_root = NULL) {
  if (is.null(project_root)) project_root <- prong1_project_root()
  cfg_path <- file.path(project_root, "config", "config.yaml")
  cfg <- yaml::read_yaml(cfg_path)
  if (is.null(cfg$prong1)) {
    stop("config.yaml is missing a 'prong1:' section.")
  }
  cfg$project_root <- project_root
  cfg
}

prong1_resolve_path <- function(path, project_root) {
  if (is.null(path) || !nzchar(path)) return(NULL)
  if (grepl("^(/|[A-Za-z]:)", path)) return(path)
  file.path(project_root, path)
}

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
  if (is.null(map_path) || !file.exists(map_path)) {
    return(default_map)
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

prong1_read_table <- function(path) {
  if (is.null(path) || !file.exists(path)) {
    stop("Input file not found: ", path)
  }
  ext <- tolower(tools::file_ext(path))
  if (ext == "rds") {
    return(as.data.frame(readRDS(path), stringsAsFactors = FALSE))
  }
  if (ext %in% c("tsv", "txt")) {
    return(as.data.frame(readr::read_tsv(path, show_col_types = FALSE), stringsAsFactors = FALSE))
  }
  as.data.frame(readr::read_csv(path, show_col_types = FALSE), stringsAsFactors = FALSE)
}

prong1_rename_mapped <- function(df, mapping) {
  missing <- setdiff(unlist(mapping, use.names = FALSE), names(df))
  if (length(missing) > 0) {
    stop("Missing mapped columns: ", paste(missing, collapse = ", "))
  }
  out <- df[, unlist(mapping, use.names = FALSE), drop = FALSE]
  names(out) <- names(mapping)
  out
}

prong1_parse_date <- function(x) {
  if (inherits(x, "Date")) return(x)
  if (inherits(x, "POSIXt")) return(as.Date(x))
  x_chr <- trimws(as.character(x))
  x_chr[x_chr == "" | tolower(x_chr) %in% c("na", "nan", "null", "none")] <- NA_character_
  parsed <- suppressWarnings(as.Date(x_chr))
  still_na <- is.na(parsed) & !is.na(x_chr)
  if (any(still_na)) {
    parsed[still_na] <- suppressWarnings(as.Date(x_chr[still_na], format = "%d/%m/%Y"))
  }
  parsed
}

prong1_normalize_sex <- function(x) {
  s <- tolower(trimws(as.character(x)))
  out <- rep(NA_character_, length(s))
  out[s %in% c("male", "m", "1", "man")] <- "male"
  out[s %in% c("female", "f", "0", "woman")] <- "female"
  out
}

prong1_normalize_icd10_level3 <- function(x) {
  cleaned <- toupper(gsub("[^A-Za-z0-9]", "", as.character(x)))
  cleaned[nchar(cleaned) < 3] <- NA_character_
  substr(cleaned, 1, 3)
}

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

prong1_sanitize_disease_name <- function(x) {
  x <- gsub("[ ,/&]", "_", as.character(x))
  x <- gsub("[()'\\.;]", "", x)
  x <- gsub("_+", "_", x)
  x
}

#' Prepare Prong 1 analysis-ready tables from generic EHR inputs.
#'
#' @return list(participants, diagnoses, disease_n_patient, report)
prong1_prepare_input <- function(
    participants_path,
    diagnoses_path,
    dictionary_path = NULL,
    column_map_path = NULL,
    n_patient_min = 100L,
    output_dir = NULL
) {
  col_map <- prong1_load_column_map(column_map_path)

  participants_raw <- prong1_read_table(participants_path)
  diagnoses_raw <- prong1_read_table(diagnoses_path)

  n_part_in <- nrow(participants_raw)
  n_diag_in <- nrow(diagnoses_raw)

  participants <- prong1_rename_mapped(participants_raw, col_map$participants)
  diagnoses <- prong1_rename_mapped(diagnoses_raw, col_map$diagnoses)

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

  n_dup_id <- sum(duplicated(participants$person_id))
  participants <- participants %>% filter(!duplicated(person_id))

  drop_sex <- sum(is.na(participants$sex))
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
      age_band = factor(
        prong1_age_band(age_at_baseline),
        levels = c("30-39", "40-49", "50-59", "60-69", "70+")
      ),
      sex = factor(sex, levels = c("female", "male")),
      assessment_centre = as.factor(assessment_centre),
      ethnicity = as.factor(ethnicity)
    )

  diagnoses <- diagnoses %>%
    mutate(
      person_id = as.character(person_id),
      icd10 = prong1_normalize_icd10_level3(icd10),
      diagnosis_date = prong1_parse_date(diagnosis_date)
    )

  n_diag_bad_icd <- sum(is.na(diagnoses$icd10))
  n_diag_bad_date <- sum(is.na(diagnoses$diagnosis_date))
  diagnoses <- diagnoses %>% filter(!is.na(icd10), !is.na(diagnosis_date))

  n_diag_orphans <- sum(!(diagnoses$person_id %in% participants$person_id))
  diagnoses <- diagnoses %>% filter(person_id %in% participants$person_id)

  diagnoses_earliest <- diagnoses %>%
    group_by(person_id, icd10) %>%
    summarise(diagnosis_date = min(diagnosis_date, na.rm = TRUE), .groups = "drop")

  dictionary <- NULL
  if (!is.null(dictionary_path) && file.exists(dictionary_path)) {
    dictionary_raw <- prong1_read_table(dictionary_path)
    dictionary <- prong1_rename_mapped(dictionary_raw, col_map$disease_dictionary) %>%
      mutate(
        icd10 = prong1_normalize_icd10_level3(icd10),
        disease_name = prong1_sanitize_disease_name(disease_name)
      ) %>%
      filter(!is.na(icd10), !is.na(disease_name), disease_name != "") %>%
      distinct(icd10, .keep_all = TRUE)
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
  }

  n_diseases_ge_min <- sum(disease_n_patient$n_patients >= n_patient_min)

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
    n_diseases = nrow(disease_n_patient),
    n_diseases_ge_n_patient_min = n_diseases_ge_min,
    n_patient_min = n_patient_min
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

prong1_print_prep_checklist <- function(report, output_dir) {
  message("Prong 1 prep checklist")
  message("  participants: ", report$n_participants_in, " -> ", report$n_participants_out)
  message("  diagnoses (earliest person x ICD): ", report$n_diagnoses_earliest_out)
  message("  diseases: ", report$n_diseases,
          " (n >= ", report$n_patient_min, ": ", report$n_diseases_ge_n_patient_min, ")")
  message("  outputs: ", output_dir)
  if (report$n_participants_out < 1 || report$n_diagnoses_earliest_out < 1) {
    message("  READY: NO — empty participants or diagnoses after cleaning")
  } else {
    message("  READY: YES — run scripts/02_run_prong1_trajectories.R next")
  }
}
