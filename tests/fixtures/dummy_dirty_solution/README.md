# Dirty dummy — gold solution (grading only)

Agents working the Match-DT skill should **derive** maps from `data/raw/dummy_dirty/` without reading this folder unless asked to grade.

## Files

| File | Purpose |
|------|---------|
| `column_map.yaml` | Source column → canonical |
| `disease_name_to_icd.yaml` | Free-text `dx_raw` → ICD-10 level-3 |
| `expected_prep_highlights.yaml` | Rough expectations after a correct prep |

## Apply before `01`

1. Replace free-text values in `diagnoses.csv` `dx_raw` using `disease_name_to_icd.yaml` (leave real ICD / dotted ICD as-is; garbage codes may remain and will be dropped).
2. Point `01` at dirty CSVs + `column_map.yaml`.
3. Expect `READY: YES` with some diagnoses dropped for bad ICD / orphans.
