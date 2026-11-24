# Config knobs (`config/config.yaml` → `prong1:`)

| Key | Role |
|-----|------|
| `participants_file` | Raw participants CSV/TSV |
| `diagnoses_file` | Raw diagnoses CSV/TSV |
| `disease_dictionary_file` | Optional dictionary |
| `column_map_file` | YAML remapping source → canonical |
| `prepared_dir` | Output of script `01` |
| `output_dir` | Output of script `02` |
| `censor_date` | Follow-up end (`YYYY-MM-DD`) |
| `n_patient_min` | Min patients per disease (default 100) |
| `min_comorbid_overlap` | Min comorbid pairs for RR step (default 20) |
| `match_ratio` | MatchIt controls per exposed (default 10) |
| `assessment_year_caliper` | Year caliper (default 3) |
| `prefilter_fdr` / `rr_fdr` / `direction_fdr` | BH FDR thresholds |
| `pair_scope` | `disease_oi` (D2 in list) or `all` |
| `exclude_d1_letters` | D1 chapters dropped before DOI FDR (default R, Z) |
| `disease_oi` | End cancers / diseases of interest |

CLI flags on scripts `01`–`03` override paths without editing YAML.

## Cohort size guidance

- Agent tests / dirty fixture: prefer ~50k participants.
- MatchIt on ~500k is slow; warn the user before `02`.
- Lowering `n_patient_min` / `min_comorbid_overlap` for tiny smoke tests is OK temporarily; restore biobank defaults for real runs.

## Real UKBB note

Disease-subset RDS files alone are not a full clinic. Matching needs a control pool including people without coded disease. Do not invent missing clinic tables.
