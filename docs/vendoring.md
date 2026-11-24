# Vendoring EarlyT_Prong1 into a parent framework

This repository is self-contained. A future parent framework can consume it as a **git submodule** or a copied tree under e.g. `vendor/EarlyT_Prong1` / `packages/EarlyT_Prong1`.

## Layout

```text
parent-framework/
  vendor/EarlyT_Prong1/    # this repo (submodule or copy)
    config/
    scripts/
    src/prong1/
    apps/match_explorer/
    data/                  # stays inside the vendored tree
    reports/
```

Run all Rscripts with working directory = the vendored project root (the folder that contains this repo’s `README.md`).

## First step: environment

```bash
cd vendor/EarlyT_Prong1
Rscript --vanilla scripts/check_prong1_env.R
# if needed:
Rscript --vanilla scripts/check_prong1_env.R --install
```

Required R ≥ 4.2 and packages: `dplyr`, `readr`, `yaml`, `jsonlite`, `stringr`, `MatchIt`, `ggplot2`, `ggrepel`, `optparse`. Optional: `shiny` (Match explorer).

## Paths

Override `prong1:` in `config/config.yaml` or pass CLI flags to scripts `01`–`03` so raw EHR and outputs live where the parent prefers. Keep Match explorer and generated `data/` inside the vendored tree unless you intentionally re-point `prepared_dir` / `output_dir`.

## Agent skill (ships with this package)

The Prong 1 Cursor skill is **versioned in this repository** at [`.cursor/skills/prong1-trajectories/`](../.cursor/skills/prong1-trajectories/). Cloning or vendoring this tree includes the skill; no separate install step.

Parent frameworks that use Cursor should keep that path intact (or symlink/copy it into the parent’s `.cursor/skills/` and keep script paths relative to this package root).

## Do not

- Rewrite Prong 1 scripts to assume the parent’s monorepo layout without updating config.
- Expect UK Biobank clinic extracts to ship inside this package.
