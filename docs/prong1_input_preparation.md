# Match-DT input schema (reference)

Transform an EHR extract into two tables (plus an optional dictionary), then run the numbered scripts in this repository. The scripts rename your columns to the canonical fields below. In the column map, each key is a canonical field and each value is the header in your file. [`config/prong1_column_map.yaml`](../config/prong1_column_map.yaml) is the demo map for the dummy CSVs. For your own extract, copy it and change the values. If your headers are already the canonical names, omit the map.

## Why two tables

1. `participants` — one row per person (matching covariates and follow-up).
2. `diagnoses` — long format, one or more rows per person (ICD-10 + date).
3. `disease_dictionary` (optional) — human-readable names.

## Canonical columns (after mapping)

### Participants

| Canonical column        | Type              | Role                                         |
| ----------------------- | ----------------- | -------------------------------------------- |
| `person_id`             | string            | Join key                                     |
| `sex`                   | string/int        | Matching (`male`/`female`, `M`/`F`, `1`/`0`) |
| `age_at_baseline`       | numeric           | Age in years at baseline (for example 21 or 67). Matching uses a band derived from this number. |
| `baseline_date`         | date `YYYY-MM-DD` | Assessment year + follow-up start            |
| `assessment_centre`     | string            | Matching                                     |
| `ethnicity`             | string            | Non-missing filter                           |
| `death_date`            | date or empty     | Censoring                                    |
| `lost_to_followup_date` | date or empty     | Censoring                                    |

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

Many EHRs store free-text condition names, SNOMED CT, ICPC-2, or vendor codes instead of ICD-10. Fill a real ICD-10 column before `scripts/01_prepare_prong1_input.R` using `scripts/profile_ehr_inputs.R` (template) and `scripts/00b_map_diagnoses.R` (JSON mapping with `confirmed` flags).

**What “level 3” means here.** One letter plus two digits (`^[A-Z][0-9]{2}`), e.g. `I10`, `E11`, `C34`. Longer/dotted codes are fine; prep keeps the first three **only if** they match that pattern. Free text is dropped as bad ICD (not truncated to `PEN`/`NOT`).

### Practical options

1. **Already ICD-10 / ICD-10-CM**

   Map that column to `icd10` in your column-map YAML. No extra conversion.
2. **SNOMED CT (or a vendor code that maps to SNOMED)**

   Join an official SNOMED → ICD-10(-CM) crosswalk, then take the ICD code. Common sources: NLM / UMLS Metathesaurus maps, SNOMED International refsets, or your local data warehouse’s terminology service. Prefer a single “primary” ICD per SNOMED concept (or document a rule when one concept maps to several ICDs).
3. **ICPC-2 or similar GP coding**

   Use a published ICPC ↔ ICD map for your country edition, then truncate to level 3. Coverage is incomplete for some symptoms; leave unmapped rows out or review them by hand.
4. **Free-text / local codes via editable JSON (recommended)**
   - Run `scripts/profile_ehr_inputs.R --write-icd-template icd10_mapping.json`.
   - Fill `icd10`, `method`, `notes`; leave `confirmed: false` until a human reviews.
   - Apply with `scripts/00b_map_diagnoses.R` (use `--require-confirmed` after review).
   - Point the column map’s `diagnoses.icd10` at the mapped column (e.g. `icd10_mapped`).
   - Crosswalk tools or agents may propose codes, but must write JSON and warn until confirmed.
5. **Do not** pass raw free text as `icd10`. Invalid strings are dropped, not truncated.

### After mapping

- Keep the original text or local code in extra columns; the column map only needs to point `icd10` at the ICD field.  
- Optional `disease_dictionary` can attach human-readable labels to level-3 codes.  
- Re-run script `01` and check `prep_report.json` (drop counters, date QC, `n_unconfirmed_icd_mappings`) before trajectories.  
- Dates may be `YYYY-MM-DD` or `DD/MM/YYYY` (also `YYYY/MM/DD`); all of `baseline_date`, `diagnosis_date`, `death_date`, and `lost_to_followup_date` are QC’d.

## Analysis parameters

See `prong1:` in [`config/config.yaml`](../config/config.yaml). Biobank-scale defaults: `n_patient_min: 100`, `min_comorbid_overlap: 20`.

## Statistical steps

1. **Prefilter** — one-sided binomial: D1→D2 rate vs background D2 prevalence.
2. **Matched RR** — MatchIt 1:N on sex, age band, baseline year, centre.
3. **Directionality** — one-sided binomial vs 50% among ordered comorbid pairs.
4. **FDR** — Benjamini–Hochberg at each stage.

Mean lag years use only cases with diagnosis date D2 after D1. D1 chapters R and Z are excluded by default before DOI FDR.
