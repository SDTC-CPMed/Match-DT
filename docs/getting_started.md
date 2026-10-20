# Getting started: install Git, install R, clone this repo

This page is for readers who are new to Git or R. After you finish these steps, return to the [README](../README.md) and run the numbered pipeline scripts.

## 1. Check what you already have

Open a terminal:

- **macOS:** Terminal (Applications → Utilities), or iTerm
- **Windows:** PowerShell or Windows Terminal (Git Bash also works after Git is installed)
- **Linux:** your usual terminal

Run:

```bash
git --version
R --version
Rscript --version
```

- If `git` prints a version (for example `git version 2.4x`), Git is installed.
- If `R` / `Rscript` print a version **4.2 or newer**, R is installed.
- If a command says “not found” / “not recognized”, install that tool below.

---

## 2. Install Git

Git downloads a copy of this project from GitHub (“clone”).

### macOS

**Option A — Xcode Command Line Tools (simple):**

```bash
xcode-select --install
```

Click **Install** and wait. Then re-check with `git --version`.

**Option B — Homebrew:**

If you use [Homebrew](https://brew.sh):

```bash
brew install git
```

### Windows

1. Download the installer from [https://git-scm.com/download/win](https://git-scm.com/download/win).
2. Run it. Defaults are fine for most users.
   - Recommended: enable **Git from the command line** when asked about PATH.
3. Close and reopen PowerShell / Terminal.
4. Check: `git --version`.

### Linux (Debian / Ubuntu)

```bash
sudo apt update
sudo apt install -y git
git --version
```

### Linux (Fedora)

```bash
sudo dnf install -y git
git --version
```

---

## 3. Install R

This pipeline needs **R ≥ 4.2** and the `Rscript` command (included with R).

### macOS

1. Open [https://cran.r-project.org](https://cran.r-project.org).
2. Click **Download R for macOS**.
3. Download the latest **R-x.x.x.pkg** for Apple silicon (arm64) or Intel, matching your Mac.
4. Open the `.pkg` and follow the installer.
5. Restart the terminal, then run:

```bash
R --version
Rscript --version
```

Optional: install [RStudio](https://posit.co/download/rstudio-desktop/) if you prefer a graphical editor. You still run the tutorial commands from a terminal (or the RStudio Terminal pane).

### Windows

1. Open [https://cran.r-project.org](https://cran.r-project.org).
2. Click **Download R for Windows** → **base** → download the installer.
3. Run the installer (defaults are fine).
4. Restart PowerShell, then:

```powershell
R --version
Rscript --version
```

If `R` is not found, either:

- Re-open the terminal after install, or
- Add R’s `bin` folder to PATH (typical location: `C:\Program Files\R\R-4.x.x\bin`), or
- Call Rscript with the full path, for example:

```powershell
& "C:\Program Files\R\R-4.4.0\bin\Rscript.exe" --version
```

### Linux (Debian / Ubuntu)

```bash
sudo apt update
sudo apt install -y r-base r-base-dev
R --version
```

For a newer R than the distro default, use [CRAN’s Ubuntu/Debian instructions](https://cran.r-project.org/bin/linux/ubuntu/).

### Linux (Fedora)

```bash
sudo dnf install -y R
R --version
```

---

## 4. Copy (clone) this GitHub repository

A **clone** creates a local folder with all project files and Git history.

1. Choose a parent folder (example: your home `Documents` or a `github` directory).
2. In the terminal:

```bash
# Go to the folder where you want the project to live
cd ~/Documents

# Download the repository
git clone https://github.com/gabdeevmaksim/EarlyT_Prong1.git

# Enter the project
cd EarlyT_Prong1
```

You should see files such as `README.md`, `scripts/`, `config/`, and `src/`.

### If you do not want to use Git

You can also download a ZIP from GitHub:

1. Open [https://github.com/gabdeevmaksim/EarlyT_Prong1](https://github.com/gabdeevmaksim/EarlyT_Prong1).
2. Click the green **Code** button → **Download ZIP**.
3. Unzip the archive.
4. In the terminal, `cd` into the unzipped folder (name may be `EarlyT_Prong1-main`).

Git clone is preferred so you can later run `git pull` to update.

### Optional: update an existing clone later

```bash
cd ~/Documents/EarlyT_Prong1
git pull
```

---

## 5. Install R packages used by this project

Still inside the project folder (`EarlyT_Prong1`):

```bash
Rscript --vanilla -e 'install.packages(c("dplyr","readr","yaml","jsonlite","stringr","MatchIt","ggplot2","ggrepel"), repos="https://cloud.r-project.org")'
```

On first install this may take several minutes. When it finishes without errors, continue with the **Quick start** section in the [README](../README.md).

---

## 6. Sanity check

From the project root:

```bash
pwd          # should end with .../EarlyT_Prong1
ls README.md scripts config
Rscript --vanilla -e 'packageVersion("MatchIt"); packageVersion("ggplot2")'
```

Then run the four tutorial steps from the README (`00` → `03`).

---

## Common problems

| Problem | What to try |
|---------|-------------|
| `git: command not found` | Install Git (section 2); close and reopen the terminal |
| `Rscript: command not found` | Install R (section 3); ensure R’s `bin` is on PATH |
| `git clone` asks for a password and fails | Use HTTPS as shown; for private repos you need a GitHub personal access token, not your account password |
| Package install fails (macOS) | Install Xcode CLT: `xcode-select --install`, then retry |
| Package install fails (Linux) | Install build tools (`r-base-dev` on Debian/Ubuntu) and retry |
| Permission errors writing under `data/` or `reports/` | Make sure you own the project folder and are not writing to a read-only location |

---

## Next step

Open [README.md](../README.md) and follow **Quick start (seeded demo)**.
