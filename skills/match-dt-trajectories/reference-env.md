# Match-DT environment

## Requirements

- R ≥ 4.2
- Required packages: `dplyr`, `readr`, `yaml`, `jsonlite`, `stringr`, `MatchIt`, `ggplot2`, `ggrepel`, `optparse`

## Check

From the project root (folder with `README.md`, `scripts/`, `config/`):

```bash
Rscript --vanilla scripts/check_prong1_env.R
```

Success prints `ENV READY: YES` and exits 0.

## Install missing packages

```bash
Rscript --vanilla scripts/check_prong1_env.R --install
```

Prefer `Rscript --vanilla` if a project `renv` setup interferes.

## macOS PATH / Rscript fallbacks

Non-login shells (many agent terminals) may omit Homebrew paths. If `Rscript` is not found:

```bash
# Apple Silicon Homebrew
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
# Intel Homebrew
export PATH="/usr/local/bin:/usr/local/sbin:$PATH"
# Or call absolute binary
/opt/homebrew/bin/Rscript --vanilla scripts/check_prong1_env.R
/usr/local/bin/Rscript --vanilla scripts/check_prong1_env.R
```

## Agent rules

- Autonomous: run check; if fail, `--install`, re-check.
- Guided: show missing list, get approval, then `--install`.
- Do not run `02`/`03` until core env is green.
