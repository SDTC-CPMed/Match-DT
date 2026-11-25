# Vendoring Match-DT into a parent framework

This repository is self-contained. A parent framework should consume it as a **git submodule** or copied tree named **`Match-DT`** at the parent root (or under e.g. `packages/Match-DT`).

## Layout

```text
parent-framework/
  Match-DT/                 # this repo (submodule or copy)
    config/
    scripts/
    src/prong1/
    data/                   # stays inside the Match-DT tree
    reports/
    skills/match-dt-trajectories/
```

Run all Rscripts with working directory = the Match-DT project root (the folder that contains this repo’s `README.md`).

## First step: environment

```bash
cd Match-DT
Rscript --vanilla scripts/check_prong1_env.R
# if needed:
Rscript --vanilla scripts/check_prong1_env.R --install
```

Required R ≥ 4.2 and packages: `dplyr`, `readr`, `yaml`, `jsonlite`, `stringr`, `MatchIt`, `ggplot2`, `ggrepel`, `optparse`.

## Paths

Override `prong1:` in `config/config.yaml` or pass CLI flags to scripts `01`–`03` so raw EHR and outputs live where the parent prefers. Keep Match explorer and generated `data/` inside the Match-DT tree unless you intentionally re-point `prepared_dir` / `output_dir`.

## Agent skill (ships with this package)

The Match-DT skill is **agent-agnostic** and versioned at [`skills/match-dt-trajectories/`](../skills/match-dt-trajectories/). Cloning or vendoring this tree includes it; no separate install step.

Point any coding agent at that directory (or `@skills/match-dt-trajectories/SKILL.md`). The optional symlink `.cursor/skills/match-dt-trajectories` exists only so Cursor can auto-discover the same files.

## Do not

- Rewrite Match-DT scripts to assume the parent’s monorepo layout without updating config.
- Expect UK Biobank clinic extracts to ship inside this package.
