# Prong 1 input schema (reference)

Transform an EHR extract into two tables (plus an optional dictionary), then run the numbered scripts in this repository. The educational demo uses **non-canonical column names** mapped via [`config/prong1_column_map.yaml`](../config/prong1_column_map.yaml).

## Why two tables

1. **`participants`** — one row per person (matching covariates and follow-up).
2. **`diagnoses`** — long format, one or more rows per person (ICD-10 + date).
3. **`disease_dictionary`** (optional) — human-readable names.

## Canonical columns (after mapping)

### Participants

| Canonical column | Type | Role |
|------------------|------|------|
| `person_id` | string | Join key |
| `sex` | string/int | Matching (`male`/`female`, `M`/`F`, `1`/`0`) |
| `age_at_baseline` | numeric | Age bands for matching |
| `baseline_date` | date `YYYY-MM-DD` | Assessment year + follow-up start |
| `assessment_centre` | string | Matching |
| `ethnicity` | string | Non-missing filter |
| `death_date` | date or empty | Censoring |
| `lost_to_followup_date` | date or empty | Censoring |

### Diagnoses

| Canonical column | Type | Role |
|------------------|------|------|
| `person_id` | string | Join |
| `icd10` | string | Truncated to ICD-10 level-3 |
| `diagnosis_date` | date | Earliest date, direction, lag |

### Disease dictionary (optional)

| Canonical column | Type |
|------------------|------|
| `icd10` | string (level-3) |
| `disease_name` | string |

## Demo column names

The dummy generator writes different names on purpose:

| Canonical | Dummy CSV column |
|-----------|------------------|
| `person_id` | `patient_uid` |
| `sex` | `gender` |
| `age_at_baseline` | `age_years` |
| `baseline_date` | `enroll_date` |
| `assessment_centre` | `clinic_site` |
| `ethnicity` | `ancestry` |
| `death_date` | `dod` |
| `lost_to_followup_date` | `exit_date` |
| `icd10` | `diagnosis_code` |
| `diagnosis_date` | `onset_date` |
| dictionary `icd10` / `disease_name` | `code` / `label` |

## Analysis parameters

See `prong1:` in [`config/config.yaml`](../config/config.yaml). Biobank-scale defaults: `n_patient_min: 100`, `min_comorbid_overlap: 20`.

## Statistical steps

1. **Prefilter** — one-sided binomial: D1→D2 rate vs background D2 prevalence.
2. **Matched RR** — MatchIt 1:N on sex, age band, baseline year, centre.
3. **Directionality** — one-sided binomial vs 50% among ordered comorbid pairs.
4. **FDR** — Benjamini–Hochberg at each stage.

Mean lag years use only cases with diagnosis date D2 after D1. D1 chapters R and Z are excluded by default before DOI FDR.
