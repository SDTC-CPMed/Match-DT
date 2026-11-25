# Troubleshooting

| Issue | Fix |
|-------|-----|
| `ENV READY: NO` / missing packages | `check_prong1_env.R --install`; check macOS PATH (`/opt/homebrew/bin`) |
| `Rscript: command not found` | Export Homebrew PATH or use absolute `Rscript` |
| Column-map file not found | Pass a real `--column-map` path; no silent fallback when path is set |
| Missing mapped columns | Error lists table name, expected vs found headers; `;` files → convert to CSV |
| Unparseable / year `0014` dates | Mixed formats must use explicit ISO/DMY parsing (fixed in prep); re-run `01` |
| `n_diag_dropped_bad_icd` high / fake `PEN`/`NOT` | Free text was truncated; use `profile_ehr_inputs.R` + `00b_map_diagnoses.R` JSON |
| `READY: NO` exit 1 | Read drop counters + samples in checklist; fix map/ICD JSON |
| HUMAN REVIEW REQUIRED | Edit `icd10_mapping.json`, set `confirmed: true`, re-run `00b` (optionally `--require-confirmed`) |
| Orphan diagnoses | ID mismatch (`P00001` vs `1`); align person_id columns |
| Dictionary `5/22` codes | Incomplete dictionary — OK, names fall back to ICD |
| Age &lt; 30 / MatchIt NA | Age bands include `20-` / `20-29`; rebuild prepared inputs |
| FUNNEL STOP: 0 pairs | Read funnel line (n_patient_min / disease_oi / min_comorbid_overlap / FDR) |
| Empty Final_trajectories / plot fails | No directed hits; check funnel FDR thresholds |
| Dirty fixture grading | Only open `tests/fixtures/dummy_dirty_solution/` if asked to grade |
