# Implementation Roadmap

Sequential, actionable checkpoints from the current codebase to the full empirical strategy in [`motherhood_penalty_wfh_research.md`](../motherhood_penalty_wfh_research.md), built on the gap analysis and proposed signatures in [`docs/LLD.md`](LLD.md). Each checkpoint is meant to be implemented and verified independently, in order — later checkpoints depend on earlier ones being done first (dependencies noted per checkpoint).

Not covered here: general test-suite construction (unit/integration tests for the *existing* functions) — that's already specified separately in [`TESTING_BLUEPRINT.md`](../TESTING_BLUEPRINT.md) and can proceed in parallel with this roadmap rather than blocking it.

---

## Checkpoint 1 — Data Validation & Quality Guard Layer

**Objective:** Add an explicit guard function that enforces `docs/LLD.md`'s hard-fail and soft-fail thresholds, so every later checkpoint builds on data that's been verified, not assumed, correct.

**Implementation Tasks:**
- New file `validation.R`, function `validate_cleaned_df(cleaned_df)`.
- Hard-fail checks (call `stop()`): `all(cleaned_df$Min == 2)`; `all(as.integer(as.character(cleaned_df$GilNK)) %in% 3:7)`; `all(cleaned_df$ShnatSeker %in% c(2017,2018,2019,2021,2022,2023))`; `sum(is.na(cleaned_df$Employed)) == 0` (same for `Mother`, `Post`); `nrow(cleaned_df) > 0`.
- Soft-fail checks (call `warning()`/`message()`, don't stop): any regression control (`MatzavMishpachti`, `Dat`, `GilNK`, `MachozMegurim`, `TeudaGvoha`) with NA rate `> 5%`; any comparative-stats-only variable with NA rate `> 70%`.
- Wire `validate_cleaned_df(cleaned_df)` into `main.R` immediately after the `load_and_clean_data()` / cache-load step, before any analysis function runs.

**Verification Step:**
```r
Rscript main.R
```
Confirm it completes with no `stop()` triggered and no unexpected warnings. Then negative-test it: `df_bad <- cleaned_df; df_bad$Min[1] <- 1; validate_cleaned_df(df_bad)` in an interactive session must `stop()` with a clear message.

---

## Checkpoint 2 — Schema-Drift Check

**Objective:** Guard the fragile positional column-drop ranges in `data_processing.R` against a future CBS file-format change silently dropping or keeping the wrong columns.

**Implementation Tasks:**
- Add `check_schema_drift(folder_path)` to `validation.R`.
- For each yearly CSV in `folder_path`, read only the header row and assert the named boundary columns of all 7 positional drop ranges (`RamatDat`/`BituachLeumi`, `Yeladim0_1Prat`/`Yeladim15_17Prat`, `MisparHachlafa`/`YachasKirvaNK`, `MisparNefashotGilAvodaV2007`/`MisparPrat`, `ChipusAvodaSherutTaasuka`/`ChipusAvodaOfenAcher`, `EizeChozemechushav`/`ChodeshKodemShaa`, `MimaHaMigbala`/`PniyaLmaasik`) occupy the same relative column position across every year's file.
- Call `check_schema_drift(folder_path)` in `main.R` before `load_and_clean_data()` runs.

**Verification Step:**
```r
Rscript main.R
```
Confirm it passes silently against the current 6 CSVs. Then negative-test: copy one CSV, swap two column positions in the header with a text editor, point `check_schema_drift()` at the copy, and confirm it throws a clear "column order changed" error rather than passing silently.

---

## Checkpoint 3 — Shared `controls` Constant

**Objective:** Eliminate the 3-way copy-pasted `controls` vector before Checkpoint 4 onward adds regression functions that would otherwise duplicate it a 4th and 5th time.

**Implementation Tasks:**
- Define `DEFAULT_CONTROLS <- c("MatzavMishpachti", "Dat", "GilNK", "MachozMegurim", "TeudaGvoha")` once, at the top of `data_processing.R` (already sourced by every other file).
- Replace the local `controls <- c(...)` block in `basic_regression.R`, `basic_reg_compared_data.R`, and `employment_by_child_age.R` with a reference to `DEFAULT_CONTROLS`.
- Replace the inline control list in `Diagnostics.R`'s `feols()` formula the same way.

**Verification Step:**
```r
Rscript main.R
```
Diff the printed `etable()` coefficients/SEs for `basic_reg()` against a saved copy of the pre-change output — they must be byte-identical (this is a pure refactor, not a logic change).

---

## Checkpoint 4 — Intensive-Margin Regression

**Objective:** Implement the second dependent-variable regression (weekly work hours) required by the research doc's core DiD specification (Part 2 §1 / Part 4 §2), which today only models the employment margin.

**Implementation Tasks:**
- New file `intensive_margin_regression.R`, function `run_intensive_margin_reg(cleaned_df, controls = DEFAULT_CONTROLS)` per the signature in `docs/LLD.md`.
- Formula: `WorkHoursCont ~ Mother + Post + Mother:Post + <controls>`, `data = filter(cleaned_df, Employed == 1)`, `cluster = ~IDPUF` (hours are only meaningful conditional on employment).
- Wire a call into `main.R` alongside the existing `basic_reg()` call.

**Verification Step:**
```r
Rscript main.R
```
Confirm the new regression prints without error. Check `nobs(model)` equals `sum(cleaned_df$Employed == 1 & !is.na(cleaned_df$WorkHoursCont))` (accounting for any additional listwise deletion on the controls). Sanity-check the `Mother:Post` coefficient is within a plausible range (single-digit to low-double-digit hours, not e.g. >40 or highly implausible in sign given the extensive-margin result from Checkpoint 3's baseline).

---

## Checkpoint 5 — Gender Placebo Test

**Objective:** Implement the fathers-vs-childless-men replication (Part 2 §3 / Part 4 §5) that tests whether the observed effect is specifically a *motherhood* penalty rather than a general parenthood or macro shift.

**Implementation Tasks:**
- Modify `load_and_clean_data()`'s signature to `load_and_clean_data(folder_path, sex_filter = c("women", "men"))`, defaulting to `"women"` (preserves `Min==2` for every existing caller); `"men"` selects `Min==1`.
- New file `gender_placebo.R`, function `run_gender_placebo(folder_path)` that calls `load_and_clean_data(folder_path, sex_filter = "men")`, runs `validate_cleaned_df()` (Checkpoint 1) against the male subsample, then calls `basic_reg()` on it.
- Before trusting the output, re-check each control's category sizes within the male subsample (a category that's sparse for women may be near-empty for men, e.g. `MisparHorimYechidim` single-father counts) — extend Checkpoint 1's soft-fail check or note any category needing collapse.

**Verification Step:**
```r
Rscript -e 'source("main.R"); run_gender_placebo("G:/My Drive/Uni/econ/csv_data")'
```
Confirm the model fits without a `fixest` collinearity/singularity error. Per the research doc's own success criterion, an **insignificant** `Mother:Post` coefficient (relabelled conceptually as the father-treatment interaction) supports the motherhood-specific interpretation — record the coefficient and p-value alongside the primary model's for direct comparison.

---

## Checkpoint 6 — WFH-Exposure Index

**Objective:** Build the occupation-level remote-work-exposure measure needed for the Triple-Differences mechanism test (Part 2 §2 / Part 4 §4).

**Implementation Tasks:**
- **Decision required first** (not code): the research doc anchors WFH exposure to the *2020* WFH variable, but 2020 is excluded from this project's sample entirely. Resolve by either (a) pulling a separate 2020-only CBS extract for this index alone, or (b) formally documenting a deviation to use 2021 as the exposure-anchor year. Record the decision in `motherhood_penalty_wfh_research.md` or a short addendum before writing code.
- New file `wfh_exposure_index.R`, function `build_wfh_exposure_index(cleaned_df, isco_col = "MishlachYad_ISCO_08_2", wfh_col = "WFH", ref_year)` per the `docs/LLD.md` signature, returning one row per occupation code with its WFH share in `ref_year`.
- Cross-reference resulting exposure values against the literature anchors the research doc names (Bloom; Cohen & Manor 2024) as a plausibility check, not an automated test.

**Verification Step:**
```r
idx <- build_wfh_exposure_index(cleaned_df, ref_year = 2021)
```
Inspect `idx` manually: confirm no `NA` exposure values silently propagate for occupation codes with nonzero observations, and confirm the ordering is directionally sane (e.g., tech-coded ISCO groups show materially higher exposure than cleaning/service-coded groups, matching the research doc's own worked example in Part 4 §4).

---

## Checkpoint 7 — DDD Mechanism Regression

**Objective:** Test whether the narrowing of the motherhood penalty is actually driven by an occupation's WFH exposure, closing out Part 2 §2's mechanism test.

**Implementation Tasks:**
- New file `ddd_regression.R`, function `run_ddd_regression(cleaned_df, exposure_index, controls = DEFAULT_CONTROLS)` per the `docs/LLD.md` signature.
- Model 1 (triple interaction): `Employed ~ Mother*Post*WFH_Exposure + controls`, joined to `exposure_index` by occupation code.
- Model 2 (second-stage mechanism): extract per-occupation `Mother:Post` estimates (β_j) from occupation-stratified runs of `basic_reg()`, then regress `β_j ~ γ_0 + γ_1·WFH_Exposure_j`.
- Depends on Checkpoint 6's `exposure_index`.

**Verification Step:**
```r
ddd <- run_ddd_regression(cleaned_df, idx)
```
Confirm both models fit without collinearity errors. Check `γ_1`'s sign matches the mechanism hypothesis (positive: higher WFH exposure associated with a larger reduction in the penalty). Cross-check the per-occupation β_j estimates feeding Model 2 are consistent in sign/magnitude with Model 1's triple-interaction coefficient.

---

## Checkpoint 8 — Age/Age² Escalation

**Objective:** Resolve the confirmed data-availability gap (no continuous age or birth-year variable exists anywhere in the current raw CBS extract) blocking Part 4 §2's stated control set.

**Implementation Tasks:** None (not a coding task). Either:
- (a) Request a wider CBS data extract that includes continuous age or birth year, then re-run Checkpoints 1–2 against the new extract before using it, **or**
- (b) Formally amend `motherhood_penalty_wfh_research.md` Part 4 §2 to specify the categorical `GilNK` age-group control already in use everywhere (which is what Part 3 §3's advisor feedback called for in the first place) instead of continuous age.

**Verification Step:** Not a test — this checkpoint's "done" state is a recorded decision. Confirm completion by checking `motherhood_penalty_wfh_research.md`'s Part 4 §2 control list matches whatever was actually decided (either a new column appears in `docs/LLD.md`'s Data Schema after a re-run of the schema dump, or the doc text is edited to drop continuous age).

---

## Checkpoint 9 — Persisted Output/Export Layer

**Objective:** Give the pipeline a durable output artifact so the research doc's "drafting findings" step (Part 1 §VI) has something to work from besides console scrollback.

**Implementation Tasks:**
- New file `export_results.R`, function `export_all_results(results_list, output_dir = "outputs")` that writes each `etable()`/summary tibble to CSV and each `ggplot` object to PNG.
- New dependency: pick one of `gt`/`officer`/`rmarkdown` if a formatted (not just CSV) table export is wanted — explicitly optional/deferred per `docs/LLD.md`; CSV + PNG alone need no new dependency.
- Wire a final `export_all_results()` call at the end of `main.R`, collecting the `invisible(list(...))` returns already produced by every existing function.

**Verification Step:**
```r
Rscript main.R
ls outputs/
```
Confirm `outputs/` contains one file per regression table (e.g. `basic_reg_table.csv`) and one PNG per plot (e.g. `child_age_plot.png`), and that opening one CSV/PNG matches what was printed to the console during the same run.

---

## Checkpoint 10 — Full-Pipeline Rollup Verification

**Objective:** Confirm the fully extended pipeline (Checkpoints 1–9) runs end-to-end and every requirement in the research doc's empirical strategy is now either implemented or explicitly, deliberately deferred.

**Implementation Tasks:** None new — this is an integration checkpoint, not a build step.

**Verification Step:**
```r
Rscript main.R
```
Must exit with status 0, no hard-fail validation errors, and produce the full set of `outputs/` artifacts from Checkpoint 9. Then manually tick every row of `docs/LLD.md`'s "HLD Gap Analysis" table against what now runs — every row should resolve to either "implemented" (Checkpoints 3–7) or "explicitly deferred with a recorded reason" (Checkpoint 8's age/age² decision, Checkpoint 9's optional formatted-report dependency).
