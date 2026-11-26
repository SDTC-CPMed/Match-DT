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
| `age_at_baseline` | numeric | Age in years (for example 21 or 67). Matching uses a band derived from this number. |
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

Level-3 = letter + two digits after strip/uppercase (`^[A-Z][0-9]{2}`, e.g. `I10`, `E11`, `C34`). Dotted codes normalize (`I10.9` → `I10`). Strings that fail this pattern (`pending`, free text) become `NA` — they are **not** truncated to `PEN`/`NOT`. Free text must be mapped via JSON + `00b_map_diagnoses.R` first.

Date columns (`baseline_date`, `diagnosis_date`, `death_date`, `lost_to_followup_date`) accept explicit `YYYY-MM-DD`, `DD/MM/YYYY`, or `YYYY/MM/DD` only (no silent format guessing).

Age bands for matching include `20-`, `20-29`, `30-39`, …, `70+`.

### Dictionary (optional)

| Column | Type |
|--------|------|
| `icd10` | level-3 code |
| `disease_name` | string |

## Column-map YAML shape

Keys stay canonical. Each value is the column name in the user's file, not a name they must rename their CSV to. The checked-in demo map is [`config/prong1_column_map.yaml`](../../config/prong1_column_map.yaml). Omit the map when the file already uses the canonical names.

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

## ICD / free-text

If the extract has disease names or local codes:

1. Build a lookup (string → ICD-10 level-3) or join SNOMED/ICPC maps.
2. Write a real ICD column, then point `icd10` at it in the map.
3. Keep original text in extra columns if useful; prep ignores unmapped fields.

Never truncate English words and call them ICD codes.

## ICD mapping JSON (human review)

Primary editable format for `scripts/00b_map_diagnoses.R` / `--write-icd-template`:

```json
{
  "metadata": { "source_file": "...", "dx_col": "dx_raw", "created_at": "..." },
  "mappings": [
    {
      "source_value": "essential hypertension",
      "n_rows": 978,
      "icd10": "I10",
      "method": "agent_inferred",
      "confidence": "high",
      "notes": "Mapped from free text; please verify.",
      "confirmed": false
    }
  ]
}
```

Set `confirmed: true` after human review. Flat `{"label":"I10"}` is accepted but treated as unconfirmed.
