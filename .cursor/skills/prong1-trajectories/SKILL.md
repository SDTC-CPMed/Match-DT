---
name: prong1-trajectories
description: >-
  Runs or guides the EarlyT Prong 1 disease→cancer trajectory pipeline:
  environment check, EHR profiling, column maps, ICD-10 level-3 prep,
  MatchIt RR, directionality, and bubble plots. Use for Prong 1, trajectories,
  MatchIt RR, column maps, dummy/dirty EHR, scripts 00–03, or env setup.
---

# Prong 1 trajectories

Self-contained R pipeline in this repo. Prefer `Rscript --vanilla` from the project root.

## Mode

Ask once if unclear:

1. **Autonomous** — check env (install missing pkgs), reshape/map data, run scripts, summarize outputs.
2. **Guided** — same steps; pause before package installs, overwriting maps/config, and long `02` runs; explain each choice.

## Checklist

```
- [ ] 0. Env: scripts/check_prong1_env.R → ENV READY: YES
- [ ] 1. Profile raw tables (or generate dummy/dirty)
- [ ] 2. Column map (+ ICD lookup if needed)
- [ ] 3. Point config/CLI paths
- [ ] 4. 01_prepare → prep_report READY
- [ ] 5. 02_trajectories → Final_trajectories.csv
- [ ] 6. 03_bubble → reports/figures/…
- [ ] 7. Summarize n trajectories / key pairs / plot path
```

## Commands

```bash
Rscript --vanilla scripts/check_prong1_env.R
# if needed: Rscript --vanilla scripts/check_prong1_env.R --install

Rscript --vanilla scripts/00_generate_dummy_data.R --seed 42 --n 50000
# dirty agent fixture:
Rscript --vanilla scripts/00_generate_dummy_data.R --seed 42 --n 50000 --dirty

Rscript --vanilla scripts/01_prepare_prong1_input.R
Rscript --vanilla scripts/02_run_prong1_trajectories.R
Rscript --vanilla scripts/03_plot_prong1_rr_bubble.R
```

Optional after `01`: `shiny::runApp("apps/match_explorer")` (needs `shiny`).

## Rules

- **Env first.** Do not run `02`/`03` until `ENV READY: YES`.
- Never pass free-text disease names as `icd10`; map to ICD-10 level-3 first.
- Prefer ~50k for agent tests; warn before MatchIt on ~500k.
- Dirty raw under `data/raw/dummy_dirty/`: **derive** maps yourself. Open `tests/fixtures/dummy_dirty_solution/` only if the user asks to grade.
- Real UKBB disease subsets ≠ full clinic; say so if controls are incomplete.
- Read detail only as needed: [reference-env.md](reference-env.md), [reference-schema.md](reference-schema.md), [reference-config.md](reference-config.md), [troubleshooting.md](troubleshooting.md).
