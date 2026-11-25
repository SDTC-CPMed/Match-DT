# Vendoring EarlyT_Prong1 into a parent framework

This repository is self-contained. A future parent framework can consume it as a **git submodule** or a copied tree under e.g. `vendor/EarlyT_Prong1` / `packages/EarlyT_Prong1`.

## Layout

```text
parent-framework/
  vendor/EarlyT_Prong1/    # this repo (submodule or copy)
    config/
    scripts/
    src/prong1/
    data/                  # stays inside the vendored tree
    reports/
    skills/prong1-trajectories/
```

Run all Rscripts with working directory = the vendored project root (the folder that contains this repo’s `README.md`).

## First step: environment

```bash
cd vendor/EarlyT_Prong1
Rscript --vanilla scripts/check_prong1_env.R
# if needed:
Rscript --vanilla scripts/check_prong1_env.R --install
```

Required R ≥ 4.2 and packages: `dplyr`, `readr`, `yaml`, `jsonlite`, `stringr`, `MatchIt`, `ggplot2`, `ggrepel`, `optparse`.

## Paths

Override `prong1:` in `config/config.yaml` or pass CLI flags to scripts `01`–`03` so raw EHR and outputs live where the parent prefers. Keep Match explorer and generated `data/` inside the vendored tree unless you intentionally re-point `prepared_dir` / `output_dir`.

## Agent skill (ships with this package)

The Prong 1 skill is **agent-agnostic** and versioned at [`skills/prong1-trajectories/`](../skills/prong1-trajectories/). Cloning or vendoring this tree includes it; no separate install step.

Point any coding agent at that directory (or `@skills/prong1-trajectories/SKILL.md`). The optional symlink `.cursor/skills/prong1-trajectories` exists only so Cursor can auto-discover the same files.

## Do not

- Rewrite Prong 1 scripts to assume the parent’s monorepo layout without updating config.
- Expect UK Biobank clinic extracts to ship inside this package.
