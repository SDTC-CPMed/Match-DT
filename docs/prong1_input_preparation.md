# Prong 1 input schema (reference)

Transform an EHR extract into two tables (plus an optional dictionary), then run the numbered scripts in this repository. The educational demo uses **non-canonical column names** mapped via [`config/prong1_column_map.yaml`](../config/prong1_column_map.yaml).

## Why two tables

1. `participants` — one row per person (matching covariates and follow-up).
2. `diagnoses` — long format, one or more rows per person (ICD-10 + date).
3. `disease_dictionary` (optional) — human-readable names.

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

Script `01` normalizes `icd10` by stripping non-alphanumerics and keeping the first three characters (for example `I10.9` → `I10`). Rows with a missing code after that step are dropped. The analysis therefore needs a real ICD-10 (or ICD-10-CM) code in that column before you run the pipeline.

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

## Converting disease names or local codes to ICD-10 level 3

Many EHRs store free-text condition names, SNOMED CT, ICPC-2, or vendor codes instead of ICD-10. Prong 1 does not map terminology for you. Fill `icd10` in your diagnoses table (or join a map) before `scripts/01_prepare_prong1_input.R`.

**What “level 3” means here.** One letter plus two digits (chapter + category), e.g. `I10`, `E11`, `C34`. Longer codes are fine in the CSV; the prep step truncates them.

### Practical options

1. **Already ICD-10 / ICD-10-CM**

   Map that column to `icd10` in your column-map YAML. No extra conversion.
2. **SNOMED CT (or a vendor code that maps to SNOMED)**

   Join an official SNOMED → ICD-10(-CM) crosswalk, then take the ICD code. Common sources: NLM / UMLS Metathesaurus maps, SNOMED International refsets, or your local data warehouse’s terminology service. Prefer a single “primary” ICD per SNOMED concept (or document a rule when one concept maps to several ICDs).
3. **ICPC-2 or similar GP coding**

   Use a published ICPC ↔ ICD map for your country edition, then truncate to level 3. Coverage is incomplete for some symptoms; leave unmapped rows out or review them by hand.
4. **Free-text disease names only**
   - **Curated lookup:** build a small table of the most frequent strings in your extract → ICD-10 level 3 (spreadsheet or YAML). Good for a short list of cancers and comorbidities.  
   - **Dictionary + string match:** normalize case/punctuation and match against WHO ICD-10 titles or a clinical synonym list; keep only high-confidence exact or near-exact hits.  
   - **Clinical NLP:** tools such as MedCAT, cTAKES, or similar concept-linking pipelines can assign SNOMED or ICD codes to narrative text; always review a sample and keep a confidence threshold.  
   - **Do not** pass raw free text as `icd10`. Three-character truncation of English words is not a valid disease code.
5. **Hybrid (recommended for research extracts)**

   Map coded fields first (SNOMED / ICPC). For remaining high-frequency free-text strings, add a manual table. Drop or flag the long tail until reviewed.

### After mapping

- Keep the original text or local code in extra columns if you like; the column map only needs to point `icd10` at the ICD field.  
- Optional `disease_dictionary` can attach human-readable labels to level-3 codes.  
- Re-run script `01` and check `prep_report.json` (`n_diag_dropped_bad_icd`, disease counts) before trajectories.

## Analysis parameters

See `prong1:` in [`config/config.yaml`](../config/config.yaml). Biobank-scale defaults: `n_patient_min: 100`, `min_comorbid_overlap: 20`.

## Statistical steps

1. **Prefilter** — one-sided binomial: D1→D2 rate vs background D2 prevalence.
2. **Matched RR** — MatchIt 1:N on sex, age band, baseline year, centre.
3. **Directionality** — one-sided binomial vs 50% among ordered comorbid pairs.
4. **FDR** — Benjamini–Hochberg at each stage.

Mean lag years use only cases with diagnosis date D2 after D1. D1 chapters R and Z are excluded by default before DOI FDR.
