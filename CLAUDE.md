# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### Setup

```r
install.packages(c("tidyverse", "fixest"))
```

Then edit `folder_path` at the top of `main.R` to point at your local CBS data folder — raw CBS
CSVs are gitignored and never present in the repo itself. Check the folder actually exists before
running anything against it in a sandbox.

### Run the pipeline

```r
source("main.R")
```

or from a shell: `Rscript main.R`. This loads/validates/cleans the data (cached as `cleaned_df.rds`
after the first run), then runs comparative stats, the three baseline regressions (pooled, Jewish,
Arab), the intensive-margin regression, child-age descriptives, and diagnostics, writing every
result to `outputs/`.

Three pieces of the empirical strategy are sourced but **not called by default** — invoke manually:

```r
# Robustness check: full sample vs. Muasak-observed-only
source("main.R"); basic_reg_comp(cleaned_df)

# Gender placebo test (loads/validates a separate male subsample)
source("gender_placebo.R"); run_gender_placebo(folder_path)

# WFH-exposure index + DDD mechanism regression
source("wfh_exposure_index.R"); source("ddd_regression.R")
idx <- build_wfh_exposure_index(cleaned_df, ref_year = 2021)
ddd <- run_ddd_regression(cleaned_df, idx)
```

### Tests

```r
Rscript run_tests.R
```

Runs the full `testthat` suite in `tests/testthat/` against fixture CSVs checked into the repo,
exiting non-zero on any failure. Any change touching a function used elsewhere (`data_processing.R`,
`DEFAULT_CONTROLS`) must be green on this suite before being considered done.

Run a single test file (faster iteration):

```r
testthat::test_file("tests/testthat/test-basic_regression.R")
```

## Architecture

- **No package layout.** This is a flat set of R scripts. Dependencies: `tidyverse` + `fixest`
  only — do not add a new dependency without flagging it first.
- **`main.R` is the orchestrator.** Every other `.R` file defines exactly one exported function and
  is `source()`d by `main.R` (or, for the three manually-invoked pieces above, sourced but not
  called).
- **Data flow:** raw yearly CBS CSVs → `check_schema_drift()` (`validation.R`) asserts named
  column-boundary positions haven't shifted, guarding the fragile positional `select(-(a:b))` drops
  in `data_processing.R` → `load_and_clean_data()` (`data_processing.R`) filters to the analysis
  sample and builds every derived variable, caching the result as `cleaned_df.rds` in the data
  folder (delete/rename it to force a rebuild after changing `data_processing.R`) →
  `validate_cleaned_df()` (`validation.R`) runs on *every* load, cached or fresh: hard-fails
  (`stop()`) on impossible states (wrong sex code, out-of-range age group, a stray 2020 row, NAs in
  `Employed`/`Mother`/`Post`, zero rows) and warns on soft thresholds (e.g. a regression control
  with >5% NA).
- **`DEFAULT_CONTROLS`** — `c("MatzavMishpachti", "Dat", "GilNK", "MachozMegurim", "TeudaGvoha")` —
  is defined once in `data_processing.R` and reused by `basic_regression.R`,
  `basic_reg_compared_data.R`, `intensive_margin_regression.R`, `employment_by_child_age.R`,
  `Diagnostics.R`, and `ddd_regression.R`. Never reintroduce a local copy in a new file.
- **Module map:**
  | File | Function | Purpose |
  |---|---|---|
  | `data_processing.R` | `load_and_clean_data()` | Loads raw CSVs, filters, builds derived variables; defines `DEFAULT_CONTROLS`. |
  | `validation.R` | `validate_cleaned_df()`, `check_schema_drift()` | Hard/soft-fail data-quality guards; CBS column-order drift guard. |
  | `comparative_statistics.R` | `run_comparative_stats()` | Missingness audit, employment-variable audit, employment rates by mother status, mobility trend plot. |
  | `basic_regression.R` | `basic_reg()` | Primary DiD: `Employed ~ Mother + Post + Mother:Post + controls`, clustered by `IDPUF`. |
  | `basic_reg_compared_data.R` | `basic_reg_comp()` | Robustness check, full sample vs. `Muasak`-observed-only. Not called by default. |
  | `intensive_margin_regression.R` | `run_intensive_margin_reg()` | `WorkHoursCont ~ Mother + Post + Mother:Post + controls`, on `Employed == 1` only. |
  | `gender_placebo.R` | `run_gender_placebo()` | Fathers vs. childless men placebo. Sourced but not called by default. |
  | `wfh_exposure_index.R` | `build_wfh_exposure_index()` | Occupation-level (ISCO-08) *realized* WFH-exposure index, anchored to 2021. Post-treatment by construction — a robustness check, not the baseline third difference. |
  | `wfh_exposure_cells.R` | `build_exposure_isco2()`, `build_exposure_cells()` | Loads the external O\*NET/Dingel–Neiman teleworkability index (`israeli_cbs_wfh_2digit.csv`), and builds pre-period shift-share exposure by demographic cell. `build_exposure_cells()` is currently defined but never called. |
  | `ddd_regression.R` | `run_ddd_regression()` | Triple-differences mechanism test on the exposure index. Depends on `wfh_exposure_index.R`; not sourced by `main.R`. |
  | `employment_by_child_age.R` | `employment_by_child_age()` | Employment rates/regression by youngest-child age bin. |
  | `Diagnostics.R` | `run_diagnostics()` | 2×2 DiD table, event-study pre-trend plot, missing-value audits. |
  | `export_results.R` | `export_all_results()` | Walks each analysis function's heterogeneous result list, writes data frames to CSV / `ggplot`s to PNG under `outputs/`. |
- **Key derived variables:** `Employed` (from `Muasak`), `Mother` (any child under 17; read as
  "Father" for the male placebo subsample), `Post` (survey year ≥ 2021), the WFH block — `WFH`
  (usual location), `WFH_RefWeek` (reference week), `WFH_Hours`, `WFH_Share`, `WFH_Arrangement`
  — all 2021+ only, all mapping CBS code `9` ("unknown") to `NA` rather than to `0`,
  `WorkHoursCont` (continuous hours derived from binned `ShaotAvodaBederechKlalNK`),
  `MishlachYad_ISCO_08_2` (2-digit ISCO-08 occupation, the join key for the exposure index/DDD
  regression).
- **`outputs/` is gitignored by default.** Several breakdowns (e.g. the Arab-women-only stratified
  regression) can produce small cells from real CBS microdata — never commit anything derived from
  it (tables, cell counts, plots) without a human explicitly reviewing it first for disclosure risk.
- **Before implementing anything**, read in order: `docs/ROADMAP.md` (the checkpoint in question),
  `docs/LLD.md` (schema/contracts), `docs/HLD.md` (why the gap exists), `TESTING_BLUEPRINT.md` (how
  to test it), and `docs/decisions/` for any resolved research-doc-vs-codebase gap. Don't implement
  from `motherhood_penalty_wfh_research.md` directly — LLD/HLD already reconcile it against the real
  codebase.
