# Match-DT — Matched Analysis of Temporal Disease Trajectories

**Match-DT** (Matched Analysis of Temporal Disease Trajectories) is a statistically based algorithm that can be applied to EHRs of different sizes and types. This repo is a self-contained **R** tutorial: turn EHR-style tables into disease→cancer relative-risk trajectories and a bubble plot of **log2(RR) vs mean lag years**.

This project is intentionally small. It does **not** include the original UK Biobank extract or the full TWIN-MAP monorepo — only what you need to learn and rerun the method on your own data.

When embedded in a parent framework, this package lives as a top-level **`Match-DT/`** folder.

## If you received a zip archive

1. Unzip the archive to a folder you can write to.
2. Open a terminal and `cd` into that folder (the directory that contains `README.md`, `scripts/`, and `config/`).
3. Install the R packages below, then follow **Quick start**.
4. You do **not** need Git. All runnable scripts live under `scripts/`.

## What you will run

```text
00 generate dummy EHR  →  01 prepare/validate  →  02 RR + directionality  →  03 bubble plot
```

Dummy CSVs play the role of an EHR and use **non-default column names** on purpose. [`config/prong1_column_map.yaml`](config/prong1_column_map.yaml) shows how to remap them to the canonical schema.

## Requirements

- R ≥ 4.2
- Packages: `dplyr`, `readr`, `yaml`, `jsonlite`, `stringr`, `MatchIt`, `ggplot2`, `ggrepel`, `optparse`

### Check / install environment

From the project root:

```bash
Rscript --vanilla scripts/check_prong1_env.R
# if packages are missing:
Rscript --vanilla scripts/check_prong1_env.R --install
```

Success prints `ENV READY: YES`. Prefer `Rscript --vanilla …` if a project-level `renv` setup gets in the way.

## Quick start (seeded demo)

From the project root (the unzipped folder):

```bash
# 0) Environment preflight
Rscript --vanilla scripts/check_prong1_env.R

# 1) Create synthetic EHR (repeatable with --seed 42)
Rscript --vanilla scripts/00_generate_dummy_data.R --seed 42

# 2) Map columns, normalize ICD-10 level-3, earliest diagnosis dates
Rscript --vanilla scripts/01_prepare_prong1_input.R

# 3) Prefilter → MatchIt RR → directionality
#    Expect several minutes on a laptop.
Rscript --vanilla scripts/02_run_prong1_trajectories.R

# 4) Bubble plot: mean lag years (x) vs log2(RR) (y) to recreate a plot like in the paper
Rscript --vanilla scripts/03_plot_prong1_rr_bubble.R
```

Dirty agent-test extract (obfuscated columns, free-text diagnoses; no column map beside the CSVs):

```bash
Rscript --vanilla scripts/00_generate_dummy_data.R --seed 42 --n 50000 --dirty
```

Gold maps for grading only: [`tests/fixtures/dummy_dirty_solution/`](tests/fixtures/dummy_dirty_solution/).

**Agent skill (included in this repo):** [`skills/match-dt-trajectories/`](skills/match-dt-trajectories/) — agent-agnostic instructions so any coding agent can run or guide env check → prep → trajectories → plot. A symlink under `.cursor/skills/` is only for Cursor discovery.


Each script accepts `--help` for its flags. Omitted path flags fall back to `config/config.yaml`.

### Profile / map dirty diagnoses (optional)

```bash
Rscript --vanilla scripts/profile_ehr_inputs.R --participants … --diagnoses … --write-icd-template icd10_mapping.json
Rscript --vanilla scripts/00b_map_diagnoses.R --diagnoses … --dx-col … --lookup icd10_mapping.json --output …_mapped.csv
Rscript --vanilla scripts/verify_prong1_run.R --expect-seed42
```

The Match explorer Shiny app is not part of the published package tree; use the scripts above for QC.

### Expected outputs

| Path | Contents |
|------|----------|
| `data/raw/dummy/*.csv` | Synthetic participants / diagnoses / dictionary |
| `data/raw/dummy/dummy_manifest.json` | Seed, planted pairs, counts |
| `data/processed/prong1_input/` | Cleaned analysis-ready tables |
| `data/processed/prong1_trajectories/Final_trajectories.csv` | Significant directed trajectories |
| `reports/figures/prong1_rr_vs_years_bubble.png` | Final figure |

With `--seed 42` and default config (`n_patient_min: 100`, `min_comorbid_overlap: 20`), the demo plants strong forward signals for `I10→C34`, `E11→C18`, `J44→C34`, `D37→C18`, and `I10→C61`. A successful run produces **five** rows in `Final_trajectories.csv` and a non-empty bubble plot.

Regenerating with the same seed yields identical CSVs (same checksums).

## Column mapping lesson

Canonical fields (what the analysis code expects) differ from the dummy export:

| Canonical | Dummy column |
|-----------|----------------|
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

Edit [`config/prong1_column_map.yaml`](config/prong1_column_map.yaml) when pointing the pipeline at real EHR extracts. Schema details: [`docs/prong1_input_preparation.md`](docs/prong1_input_preparation.md).

If your EHR uses disease **names**, SNOMED, or other local codes instead of ICD-10, map them to ICD-10 level 3 **before** script `01`. See [*Converting disease names or local codes to ICD-10 level 3*](docs/prong1_input_preparation.md#converting-disease-names-or-local-codes-to-icd-10-level-3) in that doc.

## Configuration

[`config/config.yaml`](config/config.yaml) `prong1:` block controls paths, censor date, size filters, MatchIt settings, FDR thresholds, end cancers (`disease_oi`), and D1 chapter exclusions (`R`, `Z`).

For a real cohort from your EHR, change:

```yaml
prong1:
  participants_file: path/to/your_participants.csv
  diagnoses_file: path/to/your_diagnoses.csv
  disease_dictionary_file: path/to/your_dictionary.csv   # optional
  column_map_file: config/prong1_column_map.yaml
```

Then run steps `01`–`03` (skip `00`).

## Method (short)

1. **Prefilter** — among people with disease D1, is D2-after-D1 more common than background D2 prevalence? (one-sided binomial)
2. **Matched RR** — 1:10 nearest-neighbour matching on sex, age band, baseline year (3-year caliper), and assessment centre; RR vs matched controls
3. **Directionality** — among comorbid pairs with unequal dates, is D1-before-D2 preferred over chance?
4. **FDR** — Benjamini–Hochberg at each stage

Mean lag on the plot uses only directed (D2 after D1) cases.

## Vendoring

To embed this package in a larger framework as `Match-DT/` (submodule or copy), see [`docs/vendoring.md`](docs/vendoring.md).

## Repository layout

```text
config/          config.yaml + column map
scripts/         env check, profile, 00/00b–03, verify
src/prong1/      helpers (prep, trajectories, dummy, plot)
docs/            input-schema reference and vendoring
skills/          Match-DT agent skill (versioned; ships with the package)
AGENTS.md        pointer to the agent skill
data/raw/dummy/  generated demo CSVs (recreate with script 00)
data/processed/  pipeline outputs
reports/figures/ bubble plot
```

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Missing packages / env | `Rscript --vanilla scripts/check_prong1_env.R --install` |
| Missing packages | Install the list above; prefer `Rscript --vanilla` |
| `Prepared inputs missing` | Run `01` before `02` |
| Empty `Final_trajectories.csv` | Check planted demo was generated (`00`); do not raise thresholds above biobank defaults for the dummy run |
| Matching failed for a pair | Rare on the demo; check logs and continue — other pairs still process |
| Want a smaller smoke test | `Rscript --vanilla scripts/00_generate_dummy_data.R --seed 42 --n 5000` and temporarily lower `n_patient_min` / `min_comorbid_overlap` in config |

## License

MIT — see [LICENSE](LICENSE).
