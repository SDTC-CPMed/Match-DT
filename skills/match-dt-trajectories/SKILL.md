---
name: match-dt-trajectories
description: >-
  Runs or guides the Match-DT (Matched Analysis of Temporal Disease
  Trajectories) disease→cancer pipeline: environment check, EHR profiling,
  column maps, ICD-10 JSON mapping with human confirmation, MatchIt RR,
  directionality, and bubble plots. Use for Match-DT, trajectories, MatchIt RR,
  column maps, dummy/dirty EHR, ICD mapping JSON, scripts 00–03 / 00b / profile /
  verify, or env setup.
---

# Match-DT trajectories

**Match-DT** (Matched Analysis of Temporal Disease Trajectories) is a statistically based algorithm for EHRs of different sizes and types. Self-contained R pipeline in this repo. Prefer `Rscript --vanilla` from the project root (folder named `Match-DT` when vendored).

## Mode

Ask once if unclear:

1. **Autonomous** — check env (install missing pkgs), reshape/map data, run scripts, summarize outputs. ICD mappings written with `confirmed: false` must be listed prominently in the final summary.
2. **Guided** — same steps; pause before package installs, ICD JSON confirmation, overwriting maps/config, and long `02` runs.

## Checklist

```
- [ ] 0. Env: scripts/check_prong1_env.R → ENV READY: YES
- [ ] 1. Profile raw tables (profile_ehr_inputs.R) or generate dummy/dirty
- [ ] 2. Column map YAML
- [ ] 3. If non-ICD diagnoses: write/edit icd10_mapping.json → 00b_map_diagnoses.R
- [ ] 4. Point --config / CLI paths (isolated dirs for dirty runs)
- [ ] 5. 01_prepare → READY: YES (exit 0)
- [ ] 6. 02_trajectories → Final_trajectories.csv (read funnel messages)
- [ ] 7. 03_bubble → figure PNG
- [ ] 8. verify_prong1_run.R
- [ ] 9. Summarize outputs + any unconfirmed ICD mappings for the user
```

## Commands

```bash
Rscript --vanilla scripts/check_prong1_env.R
# if needed: Rscript --vanilla scripts/check_prong1_env.R --install

# Clean demo
Rscript --vanilla scripts/00_generate_dummy_data.R --seed 42 --n 50000
Rscript --vanilla scripts/01_prepare_prong1_input.R
Rscript --vanilla scripts/02_run_prong1_trajectories.R
Rscript --vanilla scripts/03_plot_prong1_rr_bubble.R
Rscript --vanilla scripts/verify_prong1_run.R --expect-seed42

# Dirty fixture (isolated dirs — do not clobber config.yaml)
Rscript --vanilla scripts/00_generate_dummy_data.R --seed 42 --n 50000 --dirty
Rscript --vanilla scripts/profile_ehr_inputs.R \
  --participants data/raw/dummy_dirty/participants.csv \
  --diagnoses data/raw/dummy_dirty/diagnoses.csv \
  --dx-col dx_raw \
  --write-icd-template data/raw/dummy_dirty/icd10_mapping.json
# edit JSON (icd10 + confirmed), then:
Rscript --vanilla scripts/00b_map_diagnoses.R \
  --diagnoses data/raw/dummy_dirty/diagnoses.csv \
  --dx-col dx_raw \
  --lookup data/raw/dummy_dirty/icd10_mapping.json \
  --out-col icd10_mapped \
  --date-cols dx_date \
  --output data/raw/dummy_dirty/diagnoses_mapped.csv
# column map must point diagnoses.icd10 → icd10_mapped
Rscript --vanilla scripts/01_prepare_prong1_input.R \
  --participants data/raw/dummy_dirty/participants.csv \
  --diagnoses data/raw/dummy_dirty/diagnoses_mapped.csv \
  --dictionary data/raw/dummy_dirty/disease_dictionary.csv \
  --column-map path/to/dirty_column_map.yaml \
  --output-dir data/processed/prong1_input_dirty \
  --icd-map-json data/raw/dummy_dirty/icd10_mapping.json
Rscript --vanilla scripts/02_run_prong1_trajectories.R \
  --prepared-dir data/processed/prong1_input_dirty \
  --output-dir data/processed/prong1_trajectories_dirty
Rscript --vanilla scripts/03_plot_prong1_rr_bubble.R \
  --input data/processed/prong1_trajectories_dirty/Final_trajectories.csv \
  --output-png reports/figures/prong1_dirty_bubble.png
Rscript --vanilla scripts/verify_prong1_run.R \
  --prepared-dir data/processed/prong1_input_dirty \
  --trajectories-dir data/processed/prong1_trajectories_dirty \
  --figure-png reports/figures/prong1_dirty_bubble.png \
  --icd-map-json data/raw/dummy_dirty/icd10_mapping.json
```

Match explorer (`apps/match_explorer`) is **not** part of the published package layout; ignore Shiny app steps unless that directory is present locally.

## ICD-10 conversion & human confirmation

If diagnoses contain local codes or free text, tools or the agent may propose ICD-10 level-3 conversions, **but**:

1. Always write proposals to an editable JSON file (e.g. `icd10_mapping.json`) with `source_value`, `n_rows`, `icd10`, `method`/`confidence`/`notes`, and `confirmed: false`.
2. **Guided mode:** pause after generating the JSON; ask the user to review/edit/confirm before `00b` / `01` / `02`.
3. **Autonomous mode:** may populate JSON (`confirmed: false`), run the pipeline, and **must** list every inferred mapping, row impact, and JSON path in the final summary; ask the user to verify and re-run if needed.
4. Prefer `scripts/00b_map_diagnoses.R --require-confirmed` when the user has finished review.

Never pass free text as `icd10` into `01`. Never invent UKBB clinic tables.

## Rules

- **Env first.** Do not run `02`/`03` until `ENV READY: YES`.
- Prefer ~50k for agent tests; warn before MatchIt on ~500k.
- Dirty raw under `data/raw/dummy_dirty/`: **derive** maps yourself. Open `tests/fixtures/dummy_dirty_solution/` only if the user asks to grade.
- This skill is agent-agnostic (`skills/match-dt-trajectories/`).
- Detail: [reference-env.md](reference-env.md), [reference-schema.md](reference-schema.md), [reference-config.md](reference-config.md), [troubleshooting.md](troubleshooting.md).
