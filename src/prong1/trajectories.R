# Match-DT trajectory statistics on generic prepared tables.
# Logic mirrors UKBB ICD10level3 scripts 3–4 (prefilter, matched RR, directionality).

suppressPackageStartupMessages({
  library(dplyr)
  library(MatchIt)
  library(readr)
})

# prepare_input.R must be sourced first (prong1_project_root, config helpers).

# Earliest diagnosis rows for one ICD-10 code.
prong1_cases_for_code <- function(diagnoses, icd10_code) {
  diagnoses %>%
    filter(icd10 == icd10_code) %>%
    transmute(person_id = as.character(person_id), diagnosis_date)
}

# Look up disease_name from the prep TSV; fall back to the code itself.
prong1_disease_name <- function(disease_n_patient, code) {
  nm <- disease_n_patient %>% filter(icd10 == code) %>% pull(disease_name)
  if (length(nm) == 0) code else nm[[1]]
}

# Build the analysis cohort with follow-up years (death / LTFU / censor).
prong1_build_clinic <- function(participants, censor_date) {
  censor_date <- as.Date(censor_date)
  participants %>%
    mutate(
      person_id = as.character(person_id),
      sex = as.factor(sex),
      age_band = prong1_age_band_factor(age_band),
      assessment_year = as.numeric(assessment_year),
      assessment_centre = as.factor(assessment_centre),
      ethnicity = as.factor(ethnicity),
      baseline_date = as.Date(baseline_date),
      death_date = as.Date(death_date),
      lost_to_followup_date = as.Date(lost_to_followup_date),
      # os_status: 1 if died, else 0.
      os_status = ifelse(is.na(death_date), 0L, 1L),
      # Follow-up to death, else min(LTFU, censor), else censor.
      followup_years = ifelse(
        os_status == 1L,
        as.numeric(death_date - baseline_date) / 365,
        ifelse(
          is.na(lost_to_followup_date),
          as.numeric(censor_date - baseline_date) / 365,
          as.numeric(pmin(lost_to_followup_date, censor_date) - baseline_date) / 365
        )
      )
    ) %>%
    filter(
      !is.na(ethnicity),
      !is.na(age_at_baseline),
      !is.na(assessment_centre),
      !is.na(sex),
      !is.na(assessment_year)
    )
}

# Candidate D1→D2 pairs among codes with enough patients.
# pair_scope "disease_oi": D2 restricted to diseases of interest; "all": full grid.
prong1_make_pairs <- function(disease_n_patient, disease_oi, n_patient_min, pair_scope = "disease_oi") {
  kept <- disease_n_patient %>% filter(n_patients >= n_patient_min)
  if (nrow(kept) < 2) {
    return(tibble(D1 = character(), D2 = character()))
  }
  if (identical(pair_scope, "all")) {
    expand.grid(D1 = kept$icd10, D2 = kept$icd10, stringsAsFactors = FALSE) %>%
      filter(D1 != D2) %>%
      as_tibble()
  } else {
    d2_codes <- intersect(disease_oi, kept$icd10)
    d1_codes <- kept$icd10
    expand.grid(D1 = d1_codes, D2 = d2_codes, stringsAsFactors = FALSE) %>%
      filter(D1 != D2) %>%
      as_tibble()
  }
}

# Drop D1 codes whose letter chapter is excluded (e.g. R/Z symptom/status codes).
prong1_exclude_d1_letters <- function(df, letters = c("R", "Z")) {
  if (length(letters) == 0) return(df)
  pattern <- paste0("^[", paste(letters, collapse = ""), "]")
  df %>% filter(!grepl(pattern, D1))
}

# Step 1 — crude enrichment prefilter (binomial vs population D2 rate).
# Requires min_comorbid_overlap people with both D1 and D2.
prong1_run_prefilter <- function(
    pairs,
    diagnoses,
    clinic,
    disease_n_patient,
    min_comorbid_overlap = 20L
) {
  n_clinic <- nrow(clinic)
  results <- vector("list", nrow(pairs))
  if (nrow(pairs) == 0) {
    return(tibble(
      D1 = character(), D2 = character(), prefilter.p = numeric(),
      D1_counts = integer(), D2_counts = integer(),
      D1_name = character(), D2_name = character(), Note = character()
    ))
  }

  for (i in seq_len(nrow(pairs))) {
    d1_code <- pairs$D1[[i]]
    d2_code <- pairs$D2[[i]]
    d1_name <- prong1_disease_name(disease_n_patient, d1_code)
    d2_name <- prong1_disease_name(disease_n_patient, d2_code)
    message("Prefilter ", i, "/", nrow(pairs), ": ", d1_code, " -> ", d2_code)

    df_d1 <- prong1_cases_for_code(diagnoses, d1_code)
    df_d2 <- prong1_cases_for_code(diagnoses, d2_code)

    # Skip pairs with too few people who ever have both codes.
    if (length(intersect(df_d1$person_id, df_d2$person_id)) < min_comorbid_overlap) {
      results[[i]] <- data.frame(
        D1 = d1_code, D2 = d2_code, prefilter.p = NA_real_,
        D1_counts = nrow(df_d1), D2_counts = nrow(df_d2),
        D1_name = d1_name, D2_name = d2_name,
        Note = "Less than min_comorbid_overlap cases",
        stringsAsFactors = FALSE
      )
      next
    }

    # Lifetime forward count: among D1 cases, how often D2 comes after D1.
    p_d2_population <- nrow(df_d2) / n_clinic
    timing_df <- inner_join(
      df_d1 %>% transmute(person_id, diagnosis_date_d1 = diagnosis_date),
      df_d2 %>% transmute(person_id, diagnosis_date_d2 = diagnosis_date),
      by = "person_id"
    )
    c_exposed_lifetime <- sum(timing_df$diagnosis_date_d2 > timing_df$diagnosis_date_d1, na.rm = TRUE)
    n_exposed <- nrow(df_d1)

    if (n_exposed < 1 || p_d2_population <= 0 || p_d2_population >= 1) {
      results[[i]] <- data.frame(
        D1 = d1_code, D2 = d2_code, prefilter.p = NA_real_,
        D1_counts = nrow(df_d1), D2_counts = nrow(df_d2),
        D1_name = d1_name, D2_name = d2_name,
        Note = "Invalid binomial parameters",
        stringsAsFactors = FALSE
      )
      next
    }

    # One-sided test: is forward D2 rate among D1 higher than population rate?
    prefilter_test <- binom.test(
      c_exposed_lifetime, n_exposed,
      p = p_d2_population, alternative = "greater"
    )
    results[[i]] <- data.frame(
      D1 = d1_code, D2 = d2_code, prefilter.p = prefilter_test$p.value,
      D1_counts = nrow(df_d1), D2_counts = nrow(df_d2),
      D1_name = d1_name, D2_name = d2_name, Note = NA_character_,
      stringsAsFactors = FALSE
    )
  }

  bind_rows(results)
}

# Step 2 — matched relative risk + temporal directionality for prefilter hits.
prong1_run_rr_direction <- function(
    pairs_to_process,
    diagnoses,
    clinic,
    disease_n_patient,
    match_ratio = 10L,
    assessment_year_caliper = 3
) {
  results <- vector("list", nrow(pairs_to_process))
  if (nrow(pairs_to_process) == 0) {
    return(tibble(
      D1 = character(), D2 = character(), D1_name = character(), D2_name = character(),
      RR = numeric(), p_val_RR = numeric(), p_val_direction = numeric(),
      D1_counts = integer(), D2_counts = integer(),
      D1_before_D2_counts = integer(), D2_before_D1_counts = integer(),
      mean_lag_years_directed = numeric()
    ))
  }

  for (i in seq_len(nrow(pairs_to_process))) {
    d1_code <- pairs_to_process$D1[[i]]
    d2_code <- pairs_to_process$D2[[i]]
    d1_name <- prong1_disease_name(disease_n_patient, d1_code)
    d2_name <- prong1_disease_name(disease_n_patient, d2_code)
    message("RR/direction ", i, "/", nrow(pairs_to_process), ": ", d1_code, " -> ", d2_code)

    df_d1 <- prong1_cases_for_code(diagnoses, d1_code)
    df_d2 <- prong1_cases_for_code(diagnoses, d2_code)

    # Exposed = people with D1; controls = everyone else in the clinic.
    exposed_data <- clinic %>%
      filter(person_id %in% df_d1$person_id) %>%
      left_join(df_d1, by = "person_id") %>%
      mutate(exposed = 1L)
    n_exposed <- nrow(exposed_data)
    if (n_exposed < 1) next

    control_pool <- clinic %>%
      filter(!(person_id %in% df_d1$person_id)) %>%
      mutate(diagnosis_date = as.Date(NA), exposed = 0L)

    match_data_combined <- bind_rows(exposed_data, control_pool)

    # Nearest-neighbor match on sex, age band, year (±caliper), centre.
    mod_match <- tryCatch({
      matchit(
        exposed ~ sex + age_band + assessment_year + assessment_centre,
        data = match_data_combined,
        method = "nearest",
        ratio = match_ratio,
        caliper = c(assessment_year = assessment_year_caliper),
        std.caliper = FALSE
      )
    }, error = function(e) {
      message("Matching failed: ", conditionMessage(e))
      NULL
    })
    if (is.null(mod_match)) next

    matched_data <- match.data(mod_match)
    matched_controls <- matched_data %>% filter(exposed == 0L)
    if (nrow(matched_controls) < 1) next
    # Scale control D2 counts back to exposed-group size.
    ratio_matched <- n_exposed / nrow(matched_controls)

    timing_df <- inner_join(
      df_d1 %>% transmute(person_id, diagnosis_date_d1 = diagnosis_date),
      df_d2 %>% transmute(person_id, diagnosis_date_d2 = diagnosis_date),
      by = "person_id"
    )

    # RR: forward D2 among exposed vs scaled D2 rate among matched controls.
    c_exposed <- sum(timing_df$diagnosis_date_d2 > timing_df$diagnosis_date_d1, na.rm = TRUE)
    c_controls_total <- sum(matched_controls$person_id %in% df_d2$person_id)
    avg_c_control <- c_controls_total * ratio_matched
    rr_val <- ifelse(avg_c_control > 0, c_exposed / avg_c_control, NA_real_)
    p_expected <- avg_c_control / n_exposed

    p_val_significance <- if (!is.na(p_expected) && p_expected > 0 && p_expected < 1) {
      binom.test(c_exposed, n_exposed, p = p_expected, alternative = "greater")$p.value
    } else {
      NA_real_
    }

    # Directionality: among comorbid people, is D1-before-D2 more common than reverse?
    d1_before_d2 <- sum(timing_df$diagnosis_date_d1 < timing_df$diagnosis_date_d2, na.rm = TRUE)
    d2_before_d1 <- sum(timing_df$diagnosis_date_d2 < timing_df$diagnosis_date_d1, na.rm = TRUE)
    n_ord <- d1_before_d2 + d2_before_d1
    p_val_dir <- if (n_ord > 0) {
      binom.test(d1_before_d2, n_ord, p = 0.5, alternative = "greater")$p.value
    } else {
      NA_real_
    }

    # Mean lag (years) only on directed D1→D2 pairs.
    directed <- timing_df %>% filter(diagnosis_date_d2 > diagnosis_date_d1)
    mean_lag_years <- if (nrow(directed) > 0) {
      mean(as.numeric(directed$diagnosis_date_d2 - directed$diagnosis_date_d1) / 365, na.rm = TRUE)
    } else {
      NA_real_
    }

    results[[i]] <- data.frame(
      D1 = d1_code,
      D2 = d2_code,
      D1_name = d1_name,
      D2_name = d2_name,
      RR = rr_val,
      p_val_RR = p_val_significance,
      p_val_direction = p_val_dir,
      D1_counts = n_exposed,
      D2_counts = nrow(df_d2),
      D1_before_D2_counts = d1_before_d2,
      D2_before_D1_counts = d2_before_d1,
      mean_lag_years_directed = mean_lag_years,
      stringsAsFactors = FALSE
    )
  }

  bind_rows(results)
}

# Orchestrator: load prepared tables → prefilter → RR/direction → FDR finals.
prong1_run_trajectories <- function(
    prepared_dir,
    output_dir,
    censor_date,
    n_patient_min,
    min_comorbid_overlap,
    match_ratio,
    assessment_year_caliper,
    prefilter_fdr,
    rr_fdr,
    direction_fdr,
    pair_scope,
    exclude_d1_letters,
    disease_oi
) {
  participants <- readRDS(file.path(prepared_dir, "participants.rds"))
  diagnoses <- readRDS(file.path(prepared_dir, "diagnoses_earliest.rds"))
  disease_n_patient <- readr::read_tsv(
    file.path(prepared_dir, "disease_n_patient.tsv"),
    show_col_types = FALSE
  )

  clinic <- prong1_build_clinic(participants, censor_date)

  n_diseases_total <- nrow(disease_n_patient)
  n_ge_min <- sum(disease_n_patient$n_patients >= n_patient_min)
  oi_present <- intersect(disease_oi, disease_n_patient$icd10)
  oi_missing <- setdiff(disease_oi, disease_n_patient$icd10)

  message("=== Trajectory funnel ===")
  message("  Clinic N=", nrow(clinic))
  message("  Diseases total: ", n_diseases_total, " | with n >= ", n_patient_min, ": ", n_ge_min)
  message("  disease_oi present: ", length(oi_present), "/", length(disease_oi),
          if (length(oi_missing) > 0) paste0(" (missing: ", paste(oi_missing, collapse = ", "), ")") else "")

  pairs <- prong1_make_pairs(disease_n_patient, disease_oi, n_patient_min, pair_scope)
  message("  Candidate pairs: ", nrow(pairs))
  if (nrow(pairs) == 0) {
    message(
      "FUNNEL STOP: 0 candidate pairs. Causes: fewer than 2 diseases with n >= n_patient_min (",
      n_patient_min, "), or no disease_oi codes present in prepared data, or pair_scope filter."
    )
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
    readr::write_csv(
      tibble(D1 = character(), D2 = character()),
      file.path(output_dir, "Final_trajectories.csv")
    )
    return(invisible(list(prefilter = NULL, final = tibble())))
  }

  # --- Prefilter ---
  prefilter_df <- prong1_run_prefilter(
    pairs, diagnoses, clinic, disease_n_patient, min_comorbid_overlap
  )
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  saveRDS(prefilter_df, file.path(output_dir, "Step-Prefilter_result.rds"))
  readr::write_csv(prefilter_df, file.path(output_dir, "Step-Prefilter_result.csv"))
  message("  Pairs with prefilter rows (after min_comorbid_overlap=", min_comorbid_overlap, "): ", nrow(prefilter_df))
  if (nrow(prefilter_df) == 0) {
    message(
      "FUNNEL STOP: 0 pairs after min_comorbid_overlap=", min_comorbid_overlap,
      ". Lower min_comorbid_overlap or check diagnosis coverage."
    )
    readr::write_csv(tibble(), file.path(output_dir, "Final_trajectories.csv"))
    return(invisible(list(prefilter = prefilter_df, final = tibble())))
  }

  # Restrict to DOI D2s, drop excluded D1 chapters, FDR-adjust prefilter p.
  prefilter_df_doi <- prefilter_df %>%
    filter(D2 %in% disease_oi) %>%
    prong1_exclude_d1_letters(exclude_d1_letters) %>%
    mutate(prefilter.p.adjust = p.adjust(prefilter.p, method = "fdr"))

  readr::write_csv(prefilter_df_doi, file.path(output_dir, "prefilter_df_doi.csv"))
  message(
    "  After exclude_d1_letters (", paste(exclude_d1_letters, collapse = ","),
    "): ", nrow(prefilter_df_doi)
  )

  pairs_to_process <- prefilter_df_doi %>%
    filter(!is.na(prefilter.p.adjust), prefilter.p.adjust < prefilter_fdr)
  message("  Prefilter FDR hits (p.adj < ", prefilter_fdr, "): ", nrow(pairs_to_process))
  readr::write_csv(pairs_to_process, file.path(output_dir, "pairs_to_process.csv"))
  if (nrow(pairs_to_process) == 0) {
    message(
      "FUNNEL STOP: 0 prefilter FDR hits at threshold ", prefilter_fdr,
      ". No pairs proceed to MatchIt RR."
    )
    readr::write_csv(tibble(), file.path(output_dir, "Final_trajectories.csv"))
    return(invisible(list(prefilter = prefilter_df, prefilter_doi = prefilter_df_doi, final = tibble())))
  }

  # --- Matched RR + direction ---
  rr_df <- prong1_run_rr_direction(
    pairs_to_process, diagnoses, clinic, disease_n_patient,
    match_ratio = match_ratio,
    assessment_year_caliper = assessment_year_caliper
  )
  saveRDS(rr_df, file.path(output_dir, "Step-RR_direction_results.rds"))
  readr::write_csv(rr_df, file.path(output_dir, "Step-RR_direction_results.csv"))

  # Keep RR-significant pairs, then require significant forward direction.
  sig_rr_df <- rr_df %>%
    mutate(
      p.value.RR.adj = p.adjust(p_val_RR, method = "fdr"),
      RR_significant = ifelse(!is.na(p.value.RR.adj) & p.value.RR.adj < rr_fdr, "1", "-1")
    ) %>%
    filter(RR_significant == "1")
  message("  RR FDR hits (p.adj < ", rr_fdr, "): ", nrow(sig_rr_df))
  if (nrow(sig_rr_df) == 0) {
    message("FUNNEL STOP: 0 RR-significant pairs at rr_fdr=", rr_fdr, ".")
    readr::write_csv(tibble(), file.path(output_dir, "Final_trajectories.csv"))
    return(invisible(list(prefilter = prefilter_df, rr = rr_df, final = tibble())))
  }

  final_trajectories <- sig_rr_df %>%
    mutate(
      p_val_direction.adj = p.adjust(p_val_direction, method = "fdr"),
      direction_yes_no = ifelse(
        !is.na(p_val_direction.adj) & p_val_direction.adj < direction_fdr, "1", "-1"
      )
    ) %>%
    filter(direction_yes_no == "1") %>%
    arrange(D2, desc(RR))
  message("  Directed FDR hits (p.adj < ", direction_fdr, "): ", nrow(final_trajectories))
  if (nrow(final_trajectories) == 0) {
    message("FUNNEL STOP: 0 directed trajectories at direction_fdr=", direction_fdr, ".")
  }
  readr::write_csv(final_trajectories, file.path(output_dir, "Final_trajectories.csv"))

  invisible(list(
    prefilter = prefilter_df,
    prefilter_doi = prefilter_df_doi,
    rr = rr_df,
    final = final_trajectories
  ))
}
