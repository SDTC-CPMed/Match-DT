# Canonical schema and column maps

Full narrative: [`docs/prong1_input_preparation.md`](../../docs/prong1_input_preparation.md).

## Tables

1. **participants** — one row per person  
2. **diagnoses** — long format, ≥1 row per person with a coded disease  
3. **disease_dictionary** (optional) — ICD → label  

## Canonical columns

### Participants

| Column | Type | Role |
|--------|------|------|
| `person_id` | string | Join key |
| `sex` | string/int | Matching (`male`/`female`, `M`/`F`, `1`/`0`) |
| `age_at_baseline` | numeric | Age bands |
| `baseline_date` | date `YYYY-MM-DD` | Year + follow-up start |
| `assessment_centre` | string | Matching |
| `ethnicity` | string | Non-missing filter |
| `death_date` | date or empty | Censoring |
| `lost_to_followup_date` | date or empty | Censoring |

### Diagnoses

| Column | Type | Role |
|--------|------|------|
| `person_id` | string | Join |
| `icd10` | string | Truncated to ICD-10 level-3 in prep |
| `diagnosis_date` | date | Earliest date, direction, lag |

Level-3 = letter + two digits (`I10`, `E11`, `C34`). Prep strips non-alphanumerics and keeps first three characters (`I10.9` → `I10`). Free text must **not** be passed as `icd10`.

### Dictionary (optional)

| Column | Type |
|--------|------|
| `icd10` | level-3 code |
| `disease_name` | string |

## Column-map YAML shape

```yaml
participants:
  person_id: <source_col>
  sex: <source_col>
  age_at_baseline: <source_col>
  baseline_date: <source_col>
  assessment_centre: <source_col>
  ethnicity: <source_col>
  death_date: <source_col>
  lost_to_followup_date: <source_col>

diagnoses:
  person_id: <source_col>
  icd10: <source_col>
  diagnosis_date: <source_col>

disease_dictionary:
  icd10: <source_col>
  disease_name: <source_col>
```

Clean dummy map: [`config/prong1_column_map.yaml`](../../config/prong1_column_map.yaml).

## ICD / free-text

If the extract has disease names or local codes:

1. Build a lookup (string → ICD-10 level-3) or join SNOMED/ICPC maps.
2. Write a real ICD column, then point `icd10` at it in the map.
3. Keep original text in extra columns if useful; prep ignores unmapped fields.

Never truncate English words and call them ICD codes.
