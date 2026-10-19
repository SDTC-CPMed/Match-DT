# Prong 1 trajectory statistics on generic prepared tables.
# Logic mirrors UKBB ICD10level3 scripts 3–4 (prefilter, matched RR, directionality).

suppressPackageStartupMessages({
  library(dplyr)
  library(MatchIt)
  library(readr)
})

# prepare_input.R must be sourced first (prong1_project_root, config helpers).

prong1_cases_for_code <- function(diagnoses, icd10_code) {
  diagnoses %>%
    filter(icd10 == icd10_code) %>%
    transmute(person_id = as.character(person_id), diagnosis_date)
}

prong1_disease_name <- function(disease_n_patient, code) {
  nm <- disease_n_patient %>% filter(icd10 == code) %>% pull(disease_name)
  if (length(nm) == 0) code else nm[[1]]
}

prong1_build_clinic <- function(participants, censor_date) {
  censor_date <- as.Date(censor_date)
  participants %>%
    mutate(
      person_id = as.character(person_id),
      sex = as.factor(sex),
      age_band = factor(
        as.character(age_band),
        levels = c("30-39", "40-49", "50-59", "60-69", "70+")
      ),
      assessment_year = as.numeric(assessment_year),
      assessment_centre = as.factor(assessment_centre),
      ethnicity = as.factor(ethnicity),
      baseline_date = as.Date(baseline_date),
      death_date = as.Date(death_date),
      lost_to_followup_date = as.Date(lost_to_followup_date),
      os_status = ifelse(is.na(death_date), 0L, 1L),
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

prong1_exclude_d1_letters <- function(df, letters = c("R", "Z")) {
  if (length(letters) == 0) return(df)
  pattern <- paste0("^[", paste(letters, collapse = ""), "]")
  df %>% filter(!grepl(pattern, D1))
}

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
    ratio_matched <- n_exposed / nrow(matched_controls)

    timing_df <- inner_join(
      df_d1 %>% transmute(person_id, diagnosis_date_d1 = diagnosis_date),
      df_d2 %>% transmute(person_id, diagnosis_date_d2 = diagnosis_date),
      by = "person_id"
    )

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

    d1_before_d2 <- sum(timing_df$diagnosis_date_d1 < timing_df$diagnosis_date_d2, na.rm = TRUE)
    d2_before_d1 <- sum(timing_df$diagnosis_date_d2 < timing_df$diagnosis_date_d1, na.rm = TRUE)
    n_ord <- d1_before_d2 + d2_before_d1
    p_val_dir <- if (n_ord > 0) {
      binom.test(d1_before_d2, n_ord, p = 0.5, alternative = "greater")$p.value
    } else {
      NA_real_
    }

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
  pairs <- prong1_make_pairs(disease_n_patient, disease_oi, n_patient_min, pair_scope)
  message("Clinic N=", nrow(clinic), "; candidate pairs=", nrow(pairs))

  prefilter_df <- prong1_run_prefilter(
    pairs, diagnoses, clinic, disease_n_patient, min_comorbid_overlap
  )
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  saveRDS(prefilter_df, file.path(output_dir, "Step-Prefilter_result.rds"))
  readr::write_csv(prefilter_df, file.path(output_dir, "Step-Prefilter_result.csv"))

  prefilter_df_doi <- prefilter_df %>%
    filter(D2 %in% disease_oi) %>%
    prong1_exclude_d1_letters(exclude_d1_letters) %>%
    mutate(prefilter.p.adjust = p.adjust(prefilter.p, method = "fdr"))

  readr::write_csv(prefilter_df_doi, file.path(output_dir, "prefilter_df_doi.csv"))
  message("DOI pairs after D1 letter exclusion: ", nrow(prefilter_df_doi))

  pairs_to_process <- prefilter_df_doi %>%
    filter(!is.na(prefilter.p.adjust), prefilter.p.adjust < prefilter_fdr)
  message("Prefilter FDR hits: ", nrow(pairs_to_process))
  readr::write_csv(pairs_to_process, file.path(output_dir, "pairs_to_process.csv"))

  rr_df <- prong1_run_rr_direction(
    pairs_to_process, diagnoses, clinic, disease_n_patient,
    match_ratio = match_ratio,
    assessment_year_caliper = assessment_year_caliper
  )
  saveRDS(rr_df, file.path(output_dir, "Step-RR_direction_results.rds"))
  readr::write_csv(rr_df, file.path(output_dir, "Step-RR_direction_results.csv"))

  sig_rr_df <- rr_df %>%
    mutate(
      p.value.RR.adj = p.adjust(p_val_RR, method = "fdr"),
      RR_significant = ifelse(!is.na(p.value.RR.adj) & p.value.RR.adj < rr_fdr, "1", "-1")
    ) %>%
    filter(RR_significant == "1")
  message("Significant risk associations: ", nrow(sig_rr_df))

  final_trajectories <- sig_rr_df %>%
    mutate(
      p_val_direction.adj = p.adjust(p_val_direction, method = "fdr"),
      direction_yes_no = ifelse(
        !is.na(p_val_direction.adj) & p_val_direction.adj < direction_fdr, "1", "-1"
      )
    ) %>%
    filter(direction_yes_no == "1") %>%
    arrange(D2, desc(RR))
  message("Directed trajectories: ", nrow(final_trajectories))
  readr::write_csv(final_trajectories, file.path(output_dir, "Final_trajectories.csv"))

  invisible(list(
    prefilter = prefilter_df,
    prefilter_doi = prefilter_df_doi,
    rr = rr_df,
    final = final_trajectories
  ))
}
