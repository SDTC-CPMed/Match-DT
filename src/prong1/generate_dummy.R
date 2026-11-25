# Seeded synthetic EHR for Match-DT educational demos.
# Uses non-canonical column names; pair with config/prong1_column_map.yaml.

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(jsonlite)
})

# Sex restrictions for cancer codes in the dummy cohort.
# Demo rule: colorectal (C18–C20) → males only; breast (C50) → females only.
# Plus anatomically sex-specific sites.
.prong1_dummy_sex_restricted <- list(
  male = c("C18", "C19", "C20", "C61", "C62"),
  female = c("C50", "C53", "C54", "C55", "C56")
)

.prong1_dummy_sex_for_code <- function(code) {
  code3 <- substr(gsub("[^A-Za-z0-9]", "", toupper(as.character(code))), 1, 3)
  if (code3 %in% .prong1_dummy_sex_restricted$male) return("M")
  if (code3 %in% .prong1_dummy_sex_restricted$female) return("F")
  NA_character_
}

#' Generate dummy participants + long diagnoses with planted D1→D2 signals.
#'
#' @param n_participants Cohort size (default 30000).
#' @param seed RNG seed for repeatability.
#' @param output_dir Directory for CSVs + manifest.
#' @param min_age Minimum age at baseline (inclusive).
#' @param max_age Maximum age at baseline.
#' @param enroll_start Start of baseline/assessment window.
#' @param enroll_end End of baseline/assessment window (keep lag room before censor).
#' @return Invisible list of tables and manifest.
prong1_generate_dummy_data <- function(
    n_participants = 30000L,
    seed = 42L,
    output_dir = "data/raw/dummy",
    censor_date = as.Date("2022-12-30"),
    min_age = 51L,
    max_age = 75L,
    enroll_start = as.Date("1998-01-01"),
    enroll_end = as.Date("2015-12-31")
) {
  # Fix RNG so re-runs produce the same cohort and diagnosis pattern.
  set.seed(as.integer(seed))
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  n_participants <- as.integer(n_participants)
  min_age <- as.integer(min_age)
  max_age <- as.integer(max_age)
  if (min_age > max_age) stop("min_age must be <= max_age")
  enroll_start <- as.Date(enroll_start)
  enroll_end <- as.Date(enroll_end)
  if (is.na(enroll_start) || is.na(enroll_end) || enroll_end < enroll_start) {
    stop("enroll_start must be a date <= enroll_end")
  }
  if (enroll_end >= as.Date(censor_date)) {
    stop("enroll_end must be before censor_date so follow-up exists")
  }

  # Scale planted / background counts from the original 30k demo design.
  scale <- n_participants / 30000
  scale_n <- function(n) max(1L, as.integer(round(n * scale)))

  # Site and ancestry labels used as categorical covariates.
  sites <- c("site_north", "site_south", "site_east", "site_west", "site_central")
  ancestry <- c("group_A", "group_B", "group_C")

  # Wide enrollment window so assessment_year has enough spread for matching demos.
  enroll_span <- as.integer(enroll_end - enroll_start)

  id_width <- max(5L, nchar(as.character(n_participants)))

  # Core demographics table (non-canonical names on purpose).
  # Ages are uniform on [min_age, max_age] so the whole cohort is older than 50
  # when min_age = 51.
  participants <- data.frame(
    patient_uid = sprintf(paste0("P%0", id_width, "d"), seq_len(n_participants)),
    gender = sample(c("M", "F"), n_participants, replace = TRUE),
    age_years = sample.int(max_age - min_age + 1L, n_participants, replace = TRUE) + min_age - 1L,
    enroll_date = enroll_start + sample.int(enroll_span + 1L, n_participants, replace = TRUE) - 1L,
    clinic_site = sample(sites, n_participants, replace = TRUE),
    ancestry = sample(ancestry, n_participants, replace = TRUE, prob = c(0.7, 0.2, 0.1)),
    dod = as.Date(NA),
    exit_date = as.Date(NA),
    stringsAsFactors = FALSE
  )

  # ~4% die before censoring; death date is after enrollment, capped at censor_date.
  death_idx <- sample.int(n_participants, size = floor(0.04 * n_participants))
  participants$dod[death_idx] <- pmin(
    censor_date,
    participants$enroll_date[death_idx] + sample(1000:5000, length(death_idx), replace = TRUE)
  )
  # ~2% of the remaining are lost to follow-up (exit_date set, still alive).
  ltfu_pool <- setdiff(seq_len(n_participants), death_idx)
  ltfu_idx <- sample(ltfu_pool, size = floor(0.02 * n_participants))
  participants$exit_date[ltfu_idx] <- pmin(
    censor_date,
    participants$enroll_date[ltfu_idx] + sample(800:4000, length(ltfu_idx), replace = TRUE)
  )

  # Lookup: patient_uid → enroll_date (used when assigning diagnosis onsets).
  enroll_by_id <- setNames(participants$enroll_date, participants$patient_uid)
  ids <- participants$patient_uid
  male_ids <- participants$patient_uid[participants$gender == "M"]
  female_ids <- participants$patient_uid[participants$gender == "F"]

  eligible_for_code <- function(code) {
    sx <- .prong1_dummy_sex_for_code(code)
    if (identical(sx, "M")) return(male_ids)
    if (identical(sx, "F")) return(female_ids)
    ids
  }

  diag_chunks <- list()

  # Small helper: one diagnosis row per (patient, code, date).
  make_dx <- function(uids, code, dates) {
    data.frame(
      patient_uid = uids,
      diagnosis_code = code,
      onset_date = as.Date(dates),
      stringsAsFactors = FALSE
    )
  }

  # Planted D1→D2 trajectories: known temporal associations for demos/tests.
  # Sex-restricted D2s force the planted D1 pool onto that sex.
  planted_specs <- list(
    list(d1 = "I10", d2 = "C34", n_d1 = scale_n(600L), n_forward = scale_n(150L), lag_mean = 5.0, lag_sd = 1.2),
    list(d1 = "E11", d2 = "C18", n_d1 = scale_n(550L), n_forward = scale_n(140L), lag_mean = 6.0, lag_sd = 1.3),
    list(d1 = "J44", d2 = "C34", n_d1 = scale_n(500L), n_forward = scale_n(130L), lag_mean = 4.5, lag_sd = 1.0),
    list(d1 = "D37", d2 = "C18", n_d1 = scale_n(400L), n_forward = scale_n(100L), lag_mean = 3.5, lag_sd = 0.9),
    list(d1 = "I10", d2 = "C61", n_d1 = scale_n(350L), n_forward = scale_n(90L), lag_mean = 5.5, lag_sd = 1.1),
    list(d1 = "E11", d2 = "C50", n_d1 = scale_n(400L), n_forward = scale_n(110L), lag_mean = 5.0, lag_sd = 1.2),
    list(d1 = "I10", d2 = "C53", n_d1 = scale_n(250L), n_forward = scale_n(70L), lag_mean = 4.0, lag_sd = 1.0),
    list(d1 = "J44", d2 = "C62", n_d1 = scale_n(200L), n_forward = scale_n(50L), lag_mean = 3.5, lag_sd = 0.9)
  )

  used <- character(0)          # patients already assigned a planted D1 (no reuse across specs)
  planted_summary <- list()     # recorded into the JSON manifest

  for (spec in planted_specs) {
    # Intersection of D1 eligibility and D2 sex rule (if any).
    pool <- intersect(eligible_for_code(spec$d1), eligible_for_code(spec$d2))
    pool <- setdiff(pool, used)
    if (length(pool) < spec$n_d1) {
      stop(
        "Not enough unused participants for planted ", spec$d1, "→", spec$d2,
        " (need ", spec$n_d1, ", have ", length(pool), ")"
      )
    }
    d1_ids <- sample(pool, spec$n_d1)
    used <- c(used, d1_ids)
    # Subset who will also receive the forward (D2) diagnosis.
    forward_ids <- sample(d1_ids, min(spec$n_forward, length(d1_ids)))

    # D1 onset: 30–900 days after enrollment.
    d1_dates <- enroll_by_id[d1_ids] + sample(30:900, length(d1_ids), replace = TRUE)
    diag_chunks[[length(diag_chunks) + 1L]] <- make_dx(d1_ids, spec$d1, d1_dates)

    # D2 onset: D1 date + lag in years; clamp if past censor_date.
    fwd_dates_d1 <- d1_dates[match(forward_ids, d1_ids)]
    lag_years <- pmax(1.0, rnorm(length(forward_ids), mean = spec$lag_mean, sd = spec$lag_sd))
    d2_dates <- fwd_dates_d1 + as.integer(round(lag_years * 365))
    too_late <- d2_dates > censor_date
    d2_dates[too_late] <- pmax(fwd_dates_d1[too_late] + 400L, censor_date - 90L)
    diag_chunks[[length(diag_chunks) + 1L]] <- make_dx(forward_ids, spec$d2, d2_dates)

    planted_summary[[length(planted_summary) + 1L]] <- list(
      d1 = spec$d1,
      d2 = spec$d2,
      n_d1 = spec$n_d1,
      n_forward = length(forward_ids),
      sex_rule = .prong1_dummy_sex_for_code(spec$d2)
    )
  }

  diagnoses <- bind_rows(diag_chunks)

  # Background cancer incidence among eligible people who do not already have that code.
  bg_cancers <- c(
    "C18", "C19", "C20", "C22", "C25", "C34", "C43",
    "C50", "C53", "C54", "C55", "C56", "C61", "C62", "C64", "C67"
  )
  bg_rate <- 0.012
  for (code in bg_cancers) {
    have <- unique(diagnoses$patient_uid[diagnoses$diagnosis_code == code])
    candidates <- setdiff(eligible_for_code(code), have)
    n_bg <- floor(bg_rate * length(candidates))
    if (n_bg < 1L || length(candidates) < 1L) next
    pick <- sample(candidates, n_bg)
    dx_dates <- pmin(censor_date - 90L, enroll_by_id[pick] + sample(200:4000, n_bg, replace = TRUE))
    diagnoses <- bind_rows(diagnoses, make_dx(pick, code, dx_dates))
  }

  # Extra non-cancer / comorbidity rows so the EHR is not only planted signals.
  extra_specs <- list(
    list(code = "I10", n = scale_n(400L)),
    list(code = "E11", n = scale_n(350L)),
    list(code = "J44", n = scale_n(300L)),
    list(code = "D37", n = scale_n(200L)),
    list(code = "R05", n = scale_n(180L)),
    list(code = "Z72", n = scale_n(160L))
  )
  for (spec in extra_specs) {
    have <- unique(diagnoses$patient_uid[diagnoses$diagnosis_code == spec$code])
    candidates <- setdiff(eligible_for_code(spec$code), have)
    pick <- sample(candidates, min(spec$n, length(candidates)))
    dx_dates <- enroll_by_id[pick] + sample(0:2500, length(pick), replace = TRUE)
    diagnoses <- bind_rows(diagnoses, make_dx(pick, spec$code, dx_dates))
  }

  # A few longer ICD strings (I10.9) to exercise code-normalization downstream.
  long_pick <- sample(ids, min(scale_n(80L), length(ids)))
  diagnoses <- bind_rows(
    diagnoses,
    make_dx(
      long_pick,
      "I10.9",
      enroll_by_id[long_pick] + sample(10:600, length(long_pick), replace = TRUE)
    )
  )

  diagnoses <- diagnoses %>% arrange(patient_uid, onset_date)

  # Human-readable labels for the codes used above (demo dictionary).
  dictionary <- data.frame(
    code = c(
      "I10", "E11", "J44", "D37",
      "C18", "C19", "C20", "C22", "C25", "C34", "C43",
      "C50", "C53", "C54", "C55", "C56", "C61", "C62", "C64", "C67",
      "R05", "Z72"
    ),
    label = c(
      "Essential_hypertension",
      "Type_2_diabetes_mellitus",
      "Other_COPD",
      "Neoplasm_uncertain_behavior_digestive",
      "Malignant_neoplasm_of_colon",
      "Malignant_neoplasm_of_rectosigmoid_junction",
      "Malignant_neoplasm_of_rectum",
      "Malignant_neoplasm_of_liver",
      "Malignant_neoplasm_of_pancreas",
      "Malignant_neoplasm_of_bronchus_and_lung",
      "Malignant_melanoma_of_skin",
      "Malignant_neoplasm_of_breast",
      "Malignant_neoplasm_of_cervix_uteri",
      "Malignant_neoplasm_of_corpus_uteri",
      "Malignant_neoplasm_of_uterus_NOS",
      "Malignant_neoplasm_of_ovary",
      "Malignant_neoplasm_of_prostate",
      "Malignant_neoplasm_of_testis",
      "Malignant_neoplasm_of_kidney",
      "Malignant_neoplasm_of_bladder",
      "Cough",
      "Problems_related_to_lifestyle"
    ),
    stringsAsFactors = FALSE
  )

  # Blank missing dates for CSV friendliness; stringify dates for write_csv.
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

  # Level-3 code counts (first 3 alphanumeric chars) for the manifest summary.
  counts <- diagnoses %>%
    mutate(code3 = substr(gsub("[^A-Za-z0-9]", "", toupper(diagnosis_code)), 1, 3)) %>%
    distinct(patient_uid, code3) %>%
    count(code3, name = "n_patients")

  # Sidecar JSON: seed, sizes, planted pairs, counts, and actual column names.
  manifest <- list(
    seed = as.integer(seed),
    n_participants = n_participants,
    min_age = min_age,
    max_age = max_age,
    enroll_start = as.character(enroll_start),
    enroll_end = as.character(enroll_end),
    n_diagnosis_rows = nrow(diagnoses),
    sex_restricted_cancers = .prong1_dummy_sex_restricted,
    planted_trajectories = planted_summary,
    disease_counts_level3 = counts,
    column_names = list(
      participants = names(participants_out),
      diagnoses = names(diagnoses_out),
      disease_dictionary = names(dictionary)
    ),
    note = "Non-canonical column names; use config/prong1_column_map.yaml. Cohort ages >= min_age."
  )
  jsonlite::write_json(
    manifest, file.path(output_dir, "dummy_manifest.json"),
    pretty = TRUE, auto_unbox = TRUE
  )

  message("Wrote dummy EHR to ", normalizePath(output_dir))
  message("  participants: ", n_participants, " (ages ", min_age, "-", max_age, ")")
  message("  assessment window: ", enroll_start, " to ", enroll_end)
  message("  diagnosis rows: ", nrow(diagnoses))
  message("  seed: ", seed)

  invisible(list(
    participants = participants_out,
    diagnoses = diagnoses_out,
    dictionary = dictionary,
    manifest = manifest
  ))
}

# Fixed free-text strings used in dirty diagnoses (agent must map back to ICD).
.prong1_dirty_name_lookup <- data.frame(
  disease_label = c(
    "essential hypertension",
    "type 2 diabetes",
    "COPD - other",
    "uncertain digestive neoplasm",
    "colon cancer",
    "lung cancer",
    "prostate cancer",
    "breast cancer"
  ),
  icd10 = c("I10", "E11", "J44", "D37", "C18", "C34", "C61", "C50"),
  stringsAsFactors = FALSE
)

#' Generate a dirtier EHR export for agent prep tests (same epidemiology as clean dummy).
#'
#' Writes obfuscated columns, mixed encodings/dates, junk fields, free-text dx rows,
#' and incomplete dictionary. Does **not** write a working column map beside the CSVs.
prong1_generate_dirty_dummy_data <- function(
    n_participants = 50000L,
    seed = 42L,
    output_dir = "data/raw/dummy_dirty",
    censor_date = as.Date("2022-12-30"),
    min_age = 51L,
    max_age = 75L,
    enroll_start = as.Date("1998-01-01"),
    enroll_end = as.Date("2015-12-31")
) {
  set.seed(as.integer(seed))
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  tmp <- tempfile("prong1_clean_")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  clean <- prong1_generate_dummy_data(
    n_participants = n_participants,
    seed = seed,
    output_dir = tmp,
    censor_date = censor_date,
    min_age = min_age,
    max_age = max_age,
    enroll_start = enroll_start,
    enroll_end = enroll_end
  )

  participants <- clean$participants
  diagnoses <- clean$diagnoses
  dictionary <- clean$dictionary

  # --- degrade participants ---
  n <- nrow(participants)
  sex_raw <- as.character(participants$gender)
  # Mix encodings across rows (prep already accepts these).
  enc_idx <- sample.int(n)
  sex_code <- sex_raw
  sex_code[enc_idx %% 3L == 0L] <- ifelse(sex_raw[enc_idx %% 3L == 0L] == "M", "1", "0")
  sex_code[enc_idx %% 3L == 1L] <- ifelse(sex_raw[enc_idx %% 3L == 1L] == "M", "male", "female")
  # remainder stays M/F

  fmt_date_mixed <- function(d) {
    d <- as.Date(d)
    out <- as.character(d)
    na_or_empty <- is.na(d) | out == "" | out == "NA"
    pick <- !na_or_empty & (seq_along(d) %% 2L == 0L)
    out[pick] <- format(d[pick], "%d/%m/%Y")
    out[na_or_empty] <- ""
    out
  }

  participants_dirty <- data.frame(
    pt_id = participants$patient_uid,
    sex_code = sex_code,
    age = participants$age_years,
    visit_dt = fmt_date_mixed(participants$enroll_date),
    facility = participants$clinic_site,
    race_grp = participants$ancestry,
    death_dt = fmt_date_mixed(participants$dod),
    ltfu_dt = fmt_date_mixed(participants$exit_date),
    batch_id = sample(c("A", "B", "C", "D"), n, replace = TRUE),
    notes = sample(c("", "ok", "review", "legacy"), n, replace = TRUE),
    stringsAsFactors = FALSE
  )

  # Duplicate a few participant rows (prep keeps first).
  dup_n <- min(25L, max(1L, as.integer(round(n * 0.0005))))
  dup_rows <- participants_dirty[sample.int(n, dup_n), , drop = FALSE]
  participants_dirty <- rbind(participants_dirty, dup_rows)

  # --- degrade diagnoses ---
  code3 <- substr(
    gsub("[^A-Za-z0-9]", "", toupper(as.character(diagnoses$diagnosis_code))),
    1, 3
  )
  lookup <- setNames(
    .prong1_dirty_name_lookup$disease_label,
    .prong1_dirty_name_lookup$icd10
  )
  dx_raw <- as.character(diagnoses$diagnosis_code)
  # Convert a share of known codes to free-text labels.
  can_text <- code3 %in% names(lookup)
  text_idx <- which(can_text)
  if (length(text_idx) > 0) {
    n_text <- max(1L, as.integer(round(0.35 * length(text_idx))))
    pick_text <- sample(text_idx, n_text)
    dx_raw[pick_text] <- unname(lookup[code3[pick_text]])
  }
  # Sprinkle garbage codes that prep will drop after normalize.
  n_garbage <- min(40L, max(1L, as.integer(round(0.002 * nrow(diagnoses)))))
  garb_idx <- sample.int(nrow(diagnoses), n_garbage)
  dx_raw[garb_idx] <- sample(
    c("NOTACODE", "??", "pending", "Z"),
    n_garbage,
    replace = TRUE
  )
  # Keep some dotted ICD among remaining ICD-like rows.
  icd_like <- grepl("^[A-Za-z][0-9]", dx_raw) & nchar(gsub("[^A-Za-z0-9]", "", dx_raw)) >= 3
  dotted_pool <- which(icd_like & !grepl("\\.", dx_raw))
  if (length(dotted_pool) > 0) {
    n_dot <- min(length(dotted_pool), max(1L, as.integer(round(0.05 * length(dotted_pool)))))
    pick_dot <- sample(dotted_pool, n_dot)
    dx_raw[pick_dot] <- paste0(substr(gsub("[^A-Za-z0-9]", "", toupper(dx_raw[pick_dot])), 1, 3), ".9")
  }

  diagnoses_dirty <- data.frame(
    pt_id = diagnoses$patient_uid,
    dx_raw = dx_raw,
    dx_date = fmt_date_mixed(diagnoses$onset_date),
    source_system = sample(c("EHR", "claims", "registry"), nrow(diagnoses), replace = TRUE),
    stringsAsFactors = FALSE
  )

  # Orphan diagnosis rows (unknown pt_id) — prep drops them.
  orphan_n <- min(15L, nrow(diagnoses_dirty))
  orphans <- diagnoses_dirty[sample.int(nrow(diagnoses_dirty), orphan_n), , drop = FALSE]
  orphans$pt_id <- sprintf("ORPHAN%04d", seq_len(orphan_n))
  diagnoses_dirty <- rbind(diagnoses_dirty, orphans)

  # Incomplete dictionary: only a subset of codes, odd column names.
  dictionary_dirty <- data.frame(
    dx_code = dictionary$code[dictionary$code %in% c("I10", "E11", "C34", "C18", "C61")],
    dx_label = dictionary$label[dictionary$code %in% c("I10", "E11", "C34", "C18", "C61")],
    stringsAsFactors = FALSE
  )

  readr::write_csv(participants_dirty, file.path(output_dir, "participants.csv"))
  readr::write_csv(diagnoses_dirty, file.path(output_dir, "diagnoses.csv"))
  readr::write_csv(dictionary_dirty, file.path(output_dir, "disease_dictionary.csv"))

  manifest <- list(
    seed = as.integer(seed),
    n_participants = n_participants,
    dirty = TRUE,
    note = paste(
      "Obfuscated dirty EHR for agent prep tests.",
      "Derive column map and free-text→ICD lookup;",
      "do not use tests/fixtures/dummy_dirty_solution unless grading."
    ),
    column_names = list(
      participants = names(participants_dirty),
      diagnoses = names(diagnoses_dirty),
      disease_dictionary = names(dictionary_dirty)
    ),
    free_text_labels_present = unique(dx_raw[dx_raw %in% .prong1_dirty_name_lookup$disease_label])
  )
  jsonlite::write_json(
    manifest, file.path(output_dir, "dummy_manifest.json"),
    pretty = TRUE, auto_unbox = TRUE
  )

  message("Wrote dirty dummy EHR to ", normalizePath(output_dir))
  message("  participants rows (with dups): ", nrow(participants_dirty))
  message("  diagnosis rows (with orphans): ", nrow(diagnoses_dirty))
  message("  No column map written beside raw files (by design).")

  invisible(list(
    participants = participants_dirty,
    diagnoses = diagnoses_dirty,
    dictionary = dictionary_dirty,
    manifest = manifest,
    name_lookup = .prong1_dirty_name_lookup
  ))
}
