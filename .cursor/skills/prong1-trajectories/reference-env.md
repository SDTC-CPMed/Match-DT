# Prong 1 environment

## Requirements

- R ≥ 4.2
- Required packages: `dplyr`, `readr`, `yaml`, `jsonlite`, `stringr`, `MatchIt`, `ggplot2`, `ggrepel`, `optparse`
- Optional: `shiny` (Match explorer only)

## Check

From the project root (folder with `README.md`, `scripts/`, `config/`):

```bash
Rscript --vanilla scripts/check_prong1_env.R
```

Success prints `ENV READY: YES` and exits 0. Failure prints `ENV READY: NO`, lists issues, exits 1.

## Install missing packages

```bash
Rscript --vanilla scripts/check_prong1_env.R --install
```

Or:

```bash
Rscript --vanilla -e 'install.packages(c("dplyr","readr","yaml","jsonlite","stringr","MatchIt","ggplot2","ggrepel","optparse"), repos="https://cloud.r-project.org")'
```

Prefer `Rscript --vanilla` if a project `renv` setup interferes.

## Agent rules

- Autonomous mode: run check; if fail, `--install`, re-check, report what was installed.
- Guided mode: show missing list, get user approval, then `--install`.
- Do not run scripts `02`/`03` until core env is green.
- Missing `shiny` is a warning only; continue without Match explorer unless the user needs it.
