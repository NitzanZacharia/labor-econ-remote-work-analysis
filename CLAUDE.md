# Project conventions for Claude Code

- This is a set of R scripts (no package layout — no DESCRIPTION/NAMESPACE, no roxygen, no
  installed-package semantics). Dependencies: tidyverse + fixest only. Do not add a new dependency
  without flagging it in your response first.
- `main.R` is the orchestrator and stays at the repo root, alongside `run_tests.R` and
  `run_mismatch.R`. Every other .R file defines one function, lives in `scripts/`, and is
  `source()`d via a root-relative, path-qualified call (`source(file.path("scripts", "foo.R"))`) —
  never a bare filename, since cwd is assumed to be the repo root wherever sourcing happens.
- Raw CBS CSVs are gitignored and live outside the repo (real path is set locally in main.R's
  `folder_path`). Never assume they're present in a sandbox; check before running Rscript against them.
- `DEFAULT_CONTROLS <- c("MatzavMishpachti","Dat","GilNK","MachozMegurim","TeudaGvoha")`, defined
  once in `scripts/data_processing.R`, is the single source of truth once Checkpoint 3 lands —
  don't reintroduce a local copy in any new file.
- CBS survey weights (`MishkalSofi`, `MishkalShnati`, etc.) are intentionally NOT applied in any
  outcome regression — see README.md's "Known limitations". This is a deliberate scope decision,
  not a gap. Do not add `weights =` to a `feols()`/`lm()` call in this repo without raising it with
  the user first. `build_exposure_cells()` (`wfh_exposure_cells.R`) is the one existing exception —
  it weights by `MishkalSofi` when aggregating occupation exposure up to demographic cells, which is
  internal to constructing the exposure regressor and not a survey-representativeness correction.
- Before implementing anything, read: docs/ROADMAP.md (the checkpoint in question),
  docs/LLD.md (schema/contracts), docs/HLD.md (why the gap exists), TESTING_BLUEPRINT.md
  (how to test it). Don't implement from the research doc directly — LLD/HLD already reconcile
  it against the real codebase.
- Every change that touches a function used elsewhere (data_processing.R, the controls list)
  needs the full `Rscript run_tests.R` suite green before you consider the task done.
- Never commit anything derived from real CBS microdata (cell counts, tables, plots) without a
  human explicitly reviewing it first — see the disclosure-risk note in Checkpoint 9 below.
