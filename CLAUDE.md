# Project conventions for Claude Code

- This is a set of R scripts (no package layout). Dependencies: tidyverse + fixest only.
  Do not add a new dependency without flagging it in your response first.
- `main.R` is the orchestrator; every other .R file defines one function and is `source()`d.
- Raw CBS CSVs are gitignored and live outside the repo (real path is set locally in main.R's
  `folder_path`). Never assume they're present in a sandbox; check before running Rscript against them.
- `DEFAULT_CONTROLS <- c("MatzavMishpachti","Dat","GilNK","MachozMegurim","TeudaGvoha")` is the
  single source of truth once Checkpoint 3 lands — don't reintroduce a local copy in any new file.
- Before implementing anything, read: docs/ROADMAP.md (the checkpoint in question),
  docs/LLD.md (schema/contracts), docs/HLD.md (why the gap exists), TESTING_BLUEPRINT.md
  (how to test it). Don't implement from the research doc directly — LLD/HLD already reconcile
  it against the real codebase.
- Every change that touches a function used elsewhere (data_processing.R, the controls list)
  needs the full `Rscript run_tests.R` suite green before you consider the task done.
- Never commit anything derived from real CBS microdata (cell counts, tables, plots) without a
  human explicitly reviewing it first — see the disclosure-risk note in Checkpoint 9 below.
