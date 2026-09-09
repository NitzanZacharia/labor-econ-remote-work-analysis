# High-Level Design: Motherhood Penalty / WFH Analysis Pipeline

## 1. Purpose & Scope

This document describes the system that implements the research design in [`motherhood_penalty_wfh_research.md`](../motherhood_penalty_wfh_research.md) (Parts 1–4): an individual-level Difference-in-Differences (and Triple-Differences) analysis of whether the post-COVID shift to remote work altered the "motherhood penalty" in the Israeli labor market.

**Status: the original 10-checkpoint roadmap ([`docs/ROADMAP.md`](ROADMAP.md)) is complete.** Every component that document scoped is implemented, tested, and wired into `main.R`'s default run. A second tranche of work — a statistically-calibrated exposure measure, a cell-based primary DDD, and a descriptive market-mismatch exhibit — was added on top of Checkpoints 6/7 without a matching roadmap entry; see [`docs/decisions/calibrated-exposure-and-cell-ddd.md`](decisions/calibrated-exposure-and-cell-ddd.md) for that methodology's own rationale. This HLD describes the system **as it actually runs today**, not a plan toward it — treat any place this doc and the code disagree as this doc being wrong, and fix the doc.

## 2. System Architecture

**Execution model**: a single-machine, local R session (RStudio or `Rscript`). There is no database, API, scheduler, or CI — `main.R` is the sole orchestrator, run manually. State between runs is a cached file (`cleaned_df.rds`, invalidated automatically via a hash of `data_processing.R` — not just its own existence). Every result is both printed to the console and exported to `outputs/` (gitignored; disclosure-risk-gated — see §4.1).

**Layers:**

| Layer | File(s) | Role |
|---|---|---|
| Raw Data Layer | *(external — not in repo)* | Yearly CBS Labor Force Survey CSVs + `H20231031Codebook.xlsx`, at a path set locally in `main.R` (`folder_path`). Gitignored (`*.csv`). |
| Ingestion & Cleaning Layer | `data_processing.R` | `load_and_clean_data(folder_path, sex_filter)` — reads, filters, recodes, and prunes raw data into an analysis-ready data frame. Defines `DEFAULT_CONTROLS`, the single source of truth for regression controls. |
| Cached Processed-Data Layer | `cleaned_df.rds` + `cleaned_df.rds.meta.rds` | Disk-persisted cleaning output; the sidecar records a hash of `data_processing.R` so a stale cache is detected and rebuilt automatically rather than silently reused. |
| Data-Quality / Validation Layer | `validation.R` | `validate_cleaned_df()` (hard/soft-fail gates), `check_schema_drift()` (raw-CSV column-order guard), `check_idpuf_panel_structure()` (reports `IDPUF` repetition across years/the `Post` divide), `check_wfh_refweek_avadbeshavua()` (verifies a raw-data assumption stated in `data_processing.R`'s comments). All four run automatically in `main.R`; the last two are reporting-only, not gates. |
| Descriptive/Comparative Statistics Layer | `comparative_statistics.R` | `run_comparative_stats()` — missingness, employment-variable audit, group means, mobility trend. |
| Extensive-Margin Modeling Layer | `basic_regression.R`, `basic_reg_compared_data.R`, `employment_by_child_age.R` | The core `Employed ~ Mother*Post + controls` DiD (pooled + Jewish/Arab strata), a robustness check against `Muasak`-observed-only rows, and a child-age-bin breakdown. |
| Intensive-Margin Modeling Layer | `intensive_margin_regression.R`, `intensive_margin_lee_bounds.R` | The hours-worked counterpart DiD (`WorkHoursCont ~ Mother*Post + controls`, conditional on `Employed==1`), plus a Lee (2009) trimming-bounds correction for the selection risk that conditioning introduces — see [`docs/decisions/intensive-margin-lee-bounds.md`](decisions/intensive-margin-lee-bounds.md). |
| Gender Placebo Layer | `gender_placebo.R` | `run_gender_placebo(folder_path)` — reruns the core DiD on men (fathers vs. childless men) via `load_and_clean_data(..., sex_filter = "men")`, as a falsification check. Not called by default from `main.R` (manual invocation). |
| WFH-Exposure & Mechanism (DDD) Layer | `wfh_exposure_index.R`, `wfh_exposure_cells.R`, `isco_masking_diagnostics.R`, `ddd_collinearity_diagnostics.R`, `ddd_regression.R` | Builds four separate occupation/cell-level WFH-exposure measures (external, calibrated, realized, cell-based shift-share), a sensitivity check for ISCO disclosure-masking, a runtime collinearity diagnostic, and the triple-interaction DDD regressions (one primary cell-based, two specs; three occupation-level robustness variants). |
| Descriptive Mismatch Exhibit | `israeli_market_mismatch.R`, `run_mismatch.R` | `check_market_mismatch()` — a thin, descriptive-only wrapper around `calibrate_isco_exposure()` reporting how far realized Israeli WFH adoption diverges from the external teleworkability benchmark, by occupation. Invoked via `run_mismatch.R` against a cached `cleaned_df.rds`, not sourced by `main.R`. |
| Diagnostics Layer | `Diagnostics.R` | `run_diagnostics()` — 2×2 DiD table, parallel-trends event-study plot (Mother×Year, ref=2019), missing-value audits. |
| Orchestration Layer | `main.R` | Sources every module and calls them in sequence; the only entry point. |
| Output/Export Layer | `export_results.R` | `export_all_results()` — walks every analysis function's `invisible(list(...))` return and writes each data frame to CSV, each `ggplot` to PNG, under `outputs/` (gitignored; disclosure-risk review required before anything derived from it is committed). Called once, at the very end of `main.R`, covering every result including §8's exposure/DDD output. |

**Layer diagram:**

```
 [ Raw CBS LFS CSVs, external ]
              |
              v
 [ Ingestion & Cleaning: data_processing.R ]
              |
              v
 [ Cached Processed Data: cleaned_df.rds (+ hash-checked .meta.rds) ]
              |
              v
 [ Validation & Diagnostics: validation.R ]
              |
   +----------+----------+--------------------+--------------------+
   v          v          v                    v                    v
[ Comparative ] [ Extensive/Intensive ] [ Child-Age Het. ] [ Diagnostics ] [ Gender Placebo ]
[   Stats     ] [   Margin Modeling   ] [                ] [              ] [  (manual run)  ]
   |          |          |                    |                    |
   +----------+----------+--------------------+--------------------+
              |
              v
 [ WFH-Exposure & DDD Layer: wfh_exposure_index.R / wfh_exposure_cells.R /
   isco_masking_diagnostics.R / ddd_collinearity_diagnostics.R / ddd_regression.R ]
              |
   +----------+----------+
   v                     v
[ Primary cell-based DDD ]  [ 3 robustness occupation-level DDDs ]
              |
              v
 [ Output/Export: export_results.R -> outputs/ (CSV + PNG) ]
```

`israeli_market_mismatch.R` / `run_mismatch.R` sit outside this default flow — a separate, manually-run descriptive exhibit against a cached `cleaned_df.rds`, sharing `wfh_exposure_cells.R`'s `calibrate_isco_exposure()`.

## 3. Data Flow

The lifecycle of the labor force data, from raw ingestion through to regression output:

1. **Ingestion** — `load_and_clean_data()` reads every yearly CSV in `folder_path` (`read_csv` + `map_df`, tagged with a `file_source` column).
2. **Sample filtering** — restricts to `Min == 2` (women) or `Min == 1` (men) per the `sex_filter` argument (default `"women"`), `GilNK` between 3–7 (ages 25–59), and survey years `{2017,2018,2019,2021,2022,2023}` (2020 excluded as a transitional year — no raw 2020 extract exists for this project).
3. **Variable construction** (all in `data_processing.R`):
   - `Employed` — extensive-margin outcome, `1` iff `Muasak == 1`; unemployed and not-in-labor-force are both `0`.
   - `Mother`, `Post` — treatment and period dummies (children <17; post ≥ 2021). Sex-agnostic in derivation, so for the male subsample `Mother` is conceptually read as "Father" without a column rename.
   - `WFH`, `WFH_RefWeek`, `WFH_Hours`, `WFH_Share`, `WFH_Arrangement` — the WFH block. CBS's yes/no items (1=yes, 2=no, 9=unknown) are mapped so code 9 becomes `NA`, never `0`; hour items in the 90s (CBS's own "irregular"/"unknown" codes) are excluded from the hours/share computation. Only defined for `ShnatSeker >= 2021` (the questions weren't asked before).
   - `WorkHoursCont` — intensive-margin variable: bin-median lookup for regular-hours codes, plus a median imputation for irregular-hours codes (11/12) computed **separately within each `Post` period**, not pooled across 2017–2023 (pooling would blend the pre/post hour distributions and mechanically dampen any real period-specific intensity shift — exactly what the intensive-margin DiD is designed to detect).
   - `MishlachYad_ISCO_08_2`, `ISCO_masked`, `ISCO1` — the ISCO-08 occupation code, parsed to numeric; CBS's disclosure mask (`"XX"`, `"7X"`, …) is recorded explicitly (`ISCO_masked`) rather than silently becoming an unexplained `NA`, and the 1-digit major group is recovered where it survives partial masking (`ISCO1`).
   - `TeudaGvoha` (education, collapsed to 6 groups), `BirthContinent` (country of birth by continent), `WorksOutsideLocality` (commuting indicator, descriptive-only — see §4.3) — advisor-feedback-driven engineered variables.
   - Categorical controls (`MatzavMishpachti`, `Dat`, `GilNK`, `MachozMegurim`, `TeudaGvoha`) converted to factors; `DEFAULT_CONTROLS` is the single source of truth every regression function references (Checkpoint 3). Continuous age/age² was formally decided against in favor of `GilNK` — see `docs/decisions/checkpoint8-age-age2-controls.md` — this is a closed decision, not an open gap.
4. **Column pruning** — irrelevant raw columns dropped via three mechanisms: an explicit name list (`any_of()`), a regex prefix match (`matches()`), and 5 positional range drops (`select(-(a:b))`, order-dependent on the raw CSV schema, guarded by `check_schema_drift()`).
5. **Caching** — result saved to `cleaned_df.rds` alongside a hash of `data_processing.R`; a cache is only reused while that hash still matches, so a `data_processing.R` change (a coding-rule fix, a new derived column) invalidates it automatically rather than silently serving stale data.
6. **Data-quality checks** — `validate_cleaned_df()` (hard-fail on impossible states; soft-fail/warn on NA-rate thresholds), `check_idpuf_panel_structure()`, and `check_wfh_refweek_avadbeshavua()` all run immediately after load, cached or fresh.
7. **Fan-out to analysis** (from `main.R`, unless noted as manual):
   - `run_comparative_stats(cleaned_df)` — descriptive means, dependent-variable baselines.
   - `basic_reg(cleaned_df)` / `basic_reg(filter(cleaned_df, Leom==1))` / `==2` — the core DiD, pooled and Jewish/Arab-stratified.
   - `run_intensive_margin_reg(cleaned_df)` + `run_intensive_margin_lee_bounds(cleaned_df)` — the hours-worked DiD and its selection-bias-bounded counterpart.
   - `employment_by_child_age(cleaned_df)` — employment rates and a controlled regression by youngest-child age.
   - `run_diagnostics(cleaned_df)` — 2×2 DiD table and the parallel-trends event-study plot (`i.select = 2` selects the Mother×Year interaction term specifically, not the year main effects that would otherwise plot by default).
   - `run_gender_placebo(folder_path)` — **manual only**: reloads a male subsample and reruns `basic_reg()` on it.
   - **WFH-exposure measures** (four, built for different purposes, never combined into one "best" index fed to a single regression — see `docs/decisions/calibrated-exposure-and-cell-ddd.md`): `build_exposure_isco2()` (external Dingel & Neiman teleworkability), `calibrate_isco_exposure()` (statistically-calibrated swap against realized 2022-23 data, one-sided cluster-robust test), `build_wfh_exposure_index()` (realized-only, 2021-anchored), `build_exposure_cells()` (pre-period 2017-2019 shift-share exposure by demographic cell — the only one defined for non-employed rows too, and the primary DDD's exposure regressor). `check_isco_masking_sensitivity()` runs alongside as a proxy check for whether disclosure-masked occupations bias the index.
   - **Primary DDD** — `Employed ~ Mother*Post*WFH_Exposure + controls`, cell-based exposure, two specs (additive controls; interacted cell fixed effects — the standard fix for this shift-share regressor's collinearity with its own controls). `check_spec1_collinearity()` reports the additive spec's collinearity at runtime.
   - **Robustness DDDs** — `run_ddd_regression()` run three times (calibrated, external, realized occupation-level indices), each also reporting a dropped-vs-retained occupation exposure comparison for its second-stage mechanism regression.
8. **Export** — `export_all_results()` writes every result above to `outputs/` in one pass at the end of `main.R` (CSV for tables, PNG for plots). `idpuf_panel_check`'s per-`IDPUF` tables are deliberately excluded (row-level identifiable data; only its console summary is surfaced) — everything else, including the newest WFH-exposure/DDD results, is included.

## 4. Needed Components

### 4.1 Existing

| File | Function(s) | Implements | Key dependencies |
|---|---|---|---|
| `main.R` | — (orchestrator) | Pipeline sequencing and final export | — |
| `data_processing.R` | `load_and_clean_data()` | Cleaning, DV/control definition (Checkpoints 1–5's shared groundwork) | `tidyverse` |
| `validation.R` | `validate_cleaned_df()`, `check_schema_drift()`, `check_idpuf_panel_structure()`, `check_wfh_refweek_avadbeshavua()` | Checkpoints 1–2, plus two later reporting-only audits | `tidyverse` |
| `comparative_statistics.R` | `run_comparative_stats()` | Descriptive statistics | `tidyverse` |
| `basic_regression.R` | `basic_reg()` | Core DiD, extensive margin (Checkpoint 3's `DEFAULT_CONTROLS` consumer) | `fixest` |
| `basic_reg_compared_data.R` | `basic_reg_comp()` | Robustness: full sample vs. `Muasak`-observed only; not called by default | `fixest` |
| `employment_by_child_age.R` | `employment_by_child_age()` | Child-age-bin employment breakdown | `tidyverse`, `fixest` |
| `intensive_margin_regression.R` | `run_intensive_margin_reg()` | Checkpoint 4: intensive-margin DiD | `fixest` |
| `intensive_margin_lee_bounds.R` | `run_intensive_margin_lee_bounds()` | Selection-bias correction for the above — see `docs/decisions/intensive-margin-lee-bounds.md` | `fixest` (base R `lm`) |
| `gender_placebo.R` | `run_gender_placebo()` | Checkpoint 5; not called by default | `fixest` |
| `wfh_exposure_index.R` | `build_wfh_exposure_index()` | Checkpoint 6: realized-WFH occupation index (2021 anchor — see `docs/decisions/checkpoint6-wfh-anchor-year.md`) | `tidyverse` |
| `wfh_exposure_cells.R` | `build_exposure_isco2()`, `calibrate_isco_exposure()`, `build_exposure_cells()` | Beyond Checkpoint 6 — see `docs/decisions/calibrated-exposure-and-cell-ddd.md` | `tidyverse`, `fixest` |
| `isco_masking_diagnostics.R` | `check_isco_masking_sensitivity()` | Sensitivity check for the WFH-exposure index's ISCO-masking exclusion | `tidyverse`, `fixest` |
| `ddd_collinearity_diagnostics.R` | `check_spec1_collinearity()` | Runtime collinearity diagnostic for the primary DDD's additive spec (base R only — no `car` dependency) | base R (`lm`, `kappa`) |
| `ddd_regression.R` | `run_ddd_regression()` | Checkpoint 7: triple-interaction + second-stage mechanism DDD, now precision-weighted with a dropped-occupation diagnostic | `fixest` |
| `israeli_market_mismatch.R` | `check_market_mismatch()` | Descriptive-only exhibit, beyond the original roadmap | `tidyverse` |
| `run_mismatch.R` | — (script) | Invokes `check_market_mismatch()` against a cached `cleaned_df.rds` | — |
| `Diagnostics.R` | `run_diagnostics()` | 2×2 DiD, parallel-trends event study | `tidyverse`, `fixest` |
| `export_results.R` | `export_all_results()` | Checkpoint 9: persisted output layer, now covering every result including §8 | `ggplot2` |

R dependencies in use today: **`tidyverse`**, **`fixest`**. No lockfile/renv; no database, API, or scheduling dependency. `car` was considered for a VIF-based collinearity diagnostic and deliberately not added — `ddd_collinearity_diagnostics.R` implements the one VIF this project needs in base R instead (see that file's header comment).

### 4.2 Known limitations & deliberate decisions

Everything the original roadmap scoped is built. What remains are documented methodological choices and open caveats, not missing components:

| Item | Where documented | Notes |
|---|---|---|
| Survey weights (`MishkalSofi`, etc.) are not applied in any outcome regression | `README.md` Known Limitations, `CLAUDE.md` | Deliberate, not an oversight — do not add without raising it first. `build_exposure_cells()` is the one exception (weights the exposure regressor's own construction, not a survey-representativeness correction). |
| Lee (2009) bounds only handle excess selection in one direction | `docs/decisions/intensive-margin-lee-bounds.md` | Under-selection in the `Mother==1,Post==1` cell isn't addressed by this construction. |
| Calibrated-exposure / cell-based-DDD methodology | `docs/decisions/calibrated-exposure-and-cell-ddd.md` | Records why an earlier ad hoc gap-threshold rule was replaced with a statistical test, and why the DDD's primary spec is now cell-based rather than occupation-level. |
| Shift-share exposure regressor's standard errors | `main.R` §8a comment | Clustered by `IDPUF` only; a cell-level-clustered robustness check (per the shift-share/Bartik-instrument literature) has not been added. |
| ISCO disclosure-masking's effect on the exposure index | `isco_masking_diagnostics.R` | A proxy check via the coarser `ISCO1`, not a full resolution — a fully-masked ("XX") row still carries zero occupation signal at any resolution. |
| `IDPUF` cross-period repetition | `validation.R`'s `check_idpuf_panel_structure()` | Reported, not corrected — the same person can in principle contribute to both `Post==0` and `Post==1` rows. |

### 4.3 Reconciliation note

Part 3 §1 of the research doc ("Variables to Exclude") says to drop the work-mobility variable **entirely**. What's actually implemented is different: `WorksOutsideLocality` is built and reported in `run_comparative_stats()`, but deliberately excluded from every regression's `controls` list. This HLD records that as a later refinement of the written doc, not a contradiction — confirm `motherhood_penalty_wfh_research.md` reflects this if it hasn't already.
