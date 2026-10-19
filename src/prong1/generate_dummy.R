# Seeded synthetic EHR for Prong 1 educational demos.
# Uses non-canonical column names; pair with config/prong1_column_map.yaml.

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(jsonlite)
})

#' Generate dummy participants + long diagnoses with planted D1→D2 signals.
#'
#' @param n_participants Cohort size (default 30000).
#' @param seed RNG seed for repeatability.
#' @param output_dir Directory for CSVs + manifest.
#' @return Invisible list of tables and manifest.
prong1_generate_dummy_data <- function(
    n_participants = 30000L,
    seed = 42L,
    output_dir = "data/raw/dummy",
    censor_date = as.Date("2022-12-30")
) {
  set.seed(as.integer(seed))
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  sites <- c("site_north", "site_south", "site_east", "site_west", "site_central")
  ancestry <- c("group_A", "group_B", "group_C")

  enroll_start <- as.Date("2006-01-01")
  enroll_end <- as.Date("2010-12-31")
  enroll_span <- as.integer(enroll_end - enroll_start)

  participants <- data.frame(
    patient_uid = sprintf("P%05d", seq_len(n_participants)),
    gender = sample(c("M", "F"), n_participants, replace = TRUE),
    age_years = pmin(69, pmax(40, round(rnorm(n_participants, mean = 55, sd = 7)))),
    enroll_date = enroll_start + sample.int(enroll_span + 1L, n_participants, replace = TRUE) - 1L,
    clinic_site = sample(sites, n_participants, replace = TRUE),
    ancestry = sample(ancestry, n_participants, replace = TRUE, prob = c(0.7, 0.2, 0.1)),
    dod = as.Date(NA),
    exit_date = as.Date(NA),
    stringsAsFactors = FALSE
  )

  death_idx <- sample.int(n_participants, size = floor(0.04 * n_participants))
  participants$dod[death_idx] <- pmin(
    censor_date,
    participants$enroll_date[death_idx] + sample(1000:5000, length(death_idx), replace = TRUE)
  )
  ltfu_pool <- setdiff(seq_len(n_participants), death_idx)
  ltfu_idx <- sample(ltfu_pool, size = floor(0.02 * n_participants))
  participants$exit_date[ltfu_idx] <- pmin(
    censor_date,
    participants$enroll_date[ltfu_idx] + sample(800:4000, length(ltfu_idx), replace = TRUE)
  )

  enroll_by_id <- setNames(participants$enroll_date, participants$patient_uid)
  ids <- participants$patient_uid
  diag_chunks <- list()

  make_dx <- function(uids, code, dates) {
    data.frame(
      patient_uid = uids,
      diagnosis_code = code,
      onset_date = as.Date(dates),
      stringsAsFactors = FALSE
    )
  }

  planted_specs <- list(
    list(d1 = "I10", d2 = "C34", n_d1 = 600L, n_forward = 150L, lag_mean = 5.0, lag_sd = 1.2),
    list(d1 = "E11", d2 = "C18", n_d1 = 550L, n_forward = 140L, lag_mean = 6.0, lag_sd = 1.3),
    list(d1 = "J44", d2 = "C34", n_d1 = 500L, n_forward = 130L, lag_mean = 4.5, lag_sd = 1.0),
    list(d1 = "D37", d2 = "C18", n_d1 = 400L, n_forward = 100L, lag_mean = 3.5, lag_sd = 0.9),
    list(d1 = "I10", d2 = "C61", n_d1 = 350L, n_forward = 90L, lag_mean = 5.5, lag_sd = 1.1, male_only = TRUE)
  )

  used <- character(0)
  planted_summary <- list()

  for (spec in planted_specs) {
    pool <- ids
    if (isTRUE(spec$male_only)) {
      pool <- participants$patient_uid[participants$gender == "M"]
    }
    pool <- setdiff(pool, used)
    if (length(pool) < spec$n_d1) {
      stop("Not enough unused participants for planted ", spec$d1, "→", spec$d2)
    }
    d1_ids <- sample(pool, spec$n_d1)
    used <- c(used, d1_ids)
    forward_ids <- sample(d1_ids, spec$n_forward)

    d1_dates <- enroll_by_id[d1_ids] + sample(30:900, length(d1_ids), replace = TRUE)
    diag_chunks[[length(diag_chunks) + 1L]] <- make_dx(d1_ids, spec$d1, d1_dates)

    fwd_dates_d1 <- d1_dates[match(forward_ids, d1_ids)]
    lag_years <- pmax(1.0, rnorm(length(forward_ids), mean = spec$lag_mean, sd = spec$lag_sd))
    d2_dates <- fwd_dates_d1 + as.integer(round(lag_years * 365))
    too_late <- d2_dates > censor_date
    d2_dates[too_late] <- pmax(fwd_dates_d1[too_late] + 400L, censor_date - 90L)
    diag_chunks[[length(diag_chunks) + 1L]] <- make_dx(forward_ids, spec$d2, d2_dates)

    planted_summary[[length(planted_summary) + 1L]] <- list(
      d1 = spec$d1, d2 = spec$d2, n_d1 = spec$n_d1, n_forward = spec$n_forward
    )
  }

  diagnoses <- bind_rows(diag_chunks)

  bg_cancers <- c("C18", "C34", "C61")
  bg_rate <- 0.012
  for (code in bg_cancers) {
    have <- unique(diagnoses$patient_uid[diagnoses$diagnosis_code == code])
    candidates <- setdiff(ids, have)
    n_bg <- floor(bg_rate * length(candidates))
    pick <- sample(candidates, n_bg)
    dx_dates <- pmin(censor_date - 90L, enroll_by_id[pick] + sample(200:4000, n_bg, replace = TRUE))
    diagnoses <- bind_rows(diagnoses, make_dx(pick, code, dx_dates))
  }

  extra_specs <- list(
    list(code = "I10", n = 400L),
    list(code = "E11", n = 350L),
    list(code = "J44", n = 300L),
    list(code = "D37", n = 200L),
    list(code = "R05", n = 180L),
    list(code = "Z72", n = 160L)
  )
  for (spec in extra_specs) {
    have <- unique(diagnoses$patient_uid[diagnoses$diagnosis_code == spec$code])
    candidates <- setdiff(ids, have)
    pick <- sample(candidates, min(spec$n, length(candidates)))
    dx_dates <- enroll_by_id[pick] + sample(0:2500, length(pick), replace = TRUE)
    diagnoses <- bind_rows(diagnoses, make_dx(pick, spec$code, dx_dates))
  }

  long_pick <- sample(ids, 80L)
  diagnoses <- bind_rows(
    diagnoses,
    make_dx(
      long_pick,
      "I10.9",
      enroll_by_id[long_pick] + sample(10:600, length(long_pick), replace = TRUE)
    )
  )

  diagnoses <- diagnoses %>% arrange(patient_uid, onset_date)

  dictionary <- data.frame(
    code = c("I10", "E11", "J44", "D37", "C18", "C34", "C61", "R05", "Z72"),
    label = c(
      "Essential_hypertension",
      "Type_2_diabetes_mellitus",
      "Other_COPD",
      "Neoplasm_uncertain_behavior_digestive",
      "Malignant_neoplasm_of_colon",
      "Malignant_neoplasm_of_bronchus_and_lung",
      "Malignant_neoplasm_of_prostate",
      "Cough",
      "Problems_related_to_lifestyle"
    ),
    stringsAsFactors = FALSE
  )

  participants_out <- participants %>%
    mutate(
      dod = ifelse(is.na(dod), "", as.character(dod)),
      exit_date = ifelse(is.na(exit_date), "", as.character(exit_date)),
      enroll_date = as.character(enroll_date)
    )
  diagnoses_out <- diagnoses %>% mutate(onset_date = as.character(onset_date))

  readr::write_csv(participants_out, file.path(output_dir, "participants.csv"))
  readr::write_csv(diagnoses_out, file.path(output_dir, "diagnoses.csv"))
  readr::write_csv(dictionary, file.path(output_dir, "disease_dictionary.csv"))

  counts <- diagnoses %>%
    mutate(code3 = substr(gsub("[^A-Za-z0-9]", "", toupper(diagnosis_code)), 1, 3)) %>%
    distinct(patient_uid, code3) %>%
    count(code3, name = "n_patients")

  manifest <- list(
    seed = as.integer(seed),
    n_participants = n_participants,
    n_diagnosis_rows = nrow(diagnoses),
    planted_trajectories = planted_summary,
    disease_counts_level3 = counts,
    column_names = list(
      participants = names(participants_out),
      diagnoses = names(diagnoses_out),
      disease_dictionary = names(dictionary)
    ),
    note = "Non-canonical column names; use config/prong1_column_map.yaml"
  )
  jsonlite::write_json(
    manifest, file.path(output_dir, "dummy_manifest.json"),
    pretty = TRUE, auto_unbox = TRUE
  )

  message("Wrote dummy EHR to ", normalizePath(output_dir))
  message("  participants: ", n_participants)
  message("  diagnosis rows: ", nrow(diagnoses))
  message("  seed: ", seed)

  invisible(list(
    participants = participants_out,
    diagnoses = diagnoses_out,
    dictionary = dictionary,
    manifest = manifest
  ))
}
