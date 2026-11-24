# Troubleshooting

| Issue | Fix |
|-------|-----|
| `ENV READY: NO` / missing packages | `Rscript --vanilla scripts/check_prong1_env.R --install` |
| R too old | Upgrade to R ≥ 4.2 |
| Missing project paths | `cd` to EarlyT_Prong1 root (has `README.md`, `scripts/`, `config/`) |
| `renv` / package weirdness | Use `Rscript --vanilla …` |
| `Prepared inputs missing` | Run `01` before `02`; check `prepared_dir` |
| Prep drops many rows | Check sex/age/baseline/centre/ethnicity non-missing; fix date parse and column map |
| `n_diag_dropped_bad_icd` high | Diagnoses are free text or invalid; map to ICD-10 level-3 first |
| Empty `Final_trajectories.csv` | Confirm planted/demo or real signals; thresholds not raised above biobank defaults; `disease_oi` codes present |
| Matching failed for one pair | Log and continue; other pairs still process |
| Match explorer slow / huge select | Use 50k prepared dir; app uses server-side selectize for `focal_id` |
| Dirty fixture won't prep | Derive column map + name→ICD lookup; do not open `tests/fixtures/dummy_dirty_solution/` unless grading |
| Only disease subsets, no clinic | Cannot build unbiased controls; obtain full clinic or document limitation |
