# Low-Level Design: Motherhood Penalty / WFH Analysis Pipeline

Derived from [`docs/HLD.md`](HLD.md) and the actual current state of the repository. Every figure in this document (schema, types, NA rates) was pulled directly from the real cached `cleaned_df.rds` (372,741 rows × 81 columns, produced by the current `data_processing.R`), not reconstructed from reading code — see the Verification note at the end.

## Data Schema

`cleaned_df` (the output of `load_and_clean_data()`) is a flat tibble, 372,741 rows × 81 columns. Columns fall into three classes:

- **Derived (new)** — created by `data_processing.R`, not present in the raw CBS extract.
- **Type-transformed** — a raw CBS column, converted to `factor` or recoded/grouped in place (same column name, new representation).
- **Raw passthrough** — an untouched raw CBS column (Hebrew-named, numeric or character), surviving the drop step unchanged.

### Full column list (81 columns)

| # | Column | Type | Class |
|---|---|---|---|
| 1 | `file_source` | character | Derived (added at ingestion) |
| 2 | `IDPUF` | numeric | Raw passthrough (cluster ID) |
| 3 | `ShnatSeker` | numeric | Raw passthrough (survey year) |
| 4 | `MachozMegurim` | factor | Type-transformed |
| 5 | `MisparYeladimAd14MB` | numeric | Raw passthrough |
| 6 | `Yeladim0_1MB` | numeric | Raw passthrough |
| 7 | `Yeladim2_4MB` | numeric | Raw passthrough |
| 8 | `Yeladim5_9MB` | numeric | Raw passthrough |
| 9 | `Yeladim10_14MB` | numeric | Raw passthrough |
| 10 | `Yeladim15_17MB` | numeric | Raw passthrough |
| 11 | `ShaotOzeretNK` | numeric | Raw passthrough |
| 12 | `GilYeledTzairMBNK` | numeric | Raw passthrough (used by `employment_by_child_age.R`) |
| 13 | `YeladimAd17MBNK` | numeric | Raw passthrough |
| 14 | `MisparMuasakim` | numeric | Raw passthrough |
| 15 | `MisparMuasakimChelki` | numeric | Raw passthrough |
| 16 | `MisparYeladimAd17MB` | numeric | Raw passthrough (source of `Mother`) |
| 17 | `MisparHorimYechidim` | factor | Type-transformed |
| 18 | `MisparYeladimAd17LeHoreYachidMB` | numeric | Raw passthrough |
| 19 | `GilYeledTzairHoreYachidMB` | numeric | Raw passthrough |
| 20 | `Min` | numeric | Raw passthrough (sex; always `2` post-filter) |
| 21 | `MatzavMishpachti` | factor | Type-transformed |
| 22 | `SemelEretzLeda` | numeric | Raw passthrough (source of `BirthContinent`) |
| 23 | `Dat` | factor | Type-transformed |
| 24 | `TeudaGvoha` | factor | Type-transformed & grouped (11 raw codes → 6 labels) |
| 25 | `AvadBeshavua` | numeric | Raw passthrough |
| 26 | `ShaotBederechKlal` | numeric | Raw passthrough |
| 27 | `Oved35Shaot` | numeric | Raw passthrough |
| 28 | `MisraMelea` | numeric | Raw passthrough |
| 29 | `SibaLeAvodaChelkit` | numeric | Raw passthrough |
| 30 | `MeunyanLaavod` | numeric | Raw passthrough |
| 31 | `AvadShanaAchrona` | numeric | Raw passthrough |
| 32 | `NayadutYishuvAvoda` | numeric | Raw passthrough |
| 33 | `SemelAnafKalkali` | character | Raw passthrough |
| 34 | `SemelMishlachYad` | character | Raw passthrough |
| 35 | `MaamadAvoda` | numeric | Raw passthrough |
| 36 | `KamaChodashimAvadBashana` | numeric | Raw passthrough (unused since the `Employed` redefinition) |
| 37 | `SibaLoAvadHashana` | numeric | Raw passthrough |
| 38 | `Leom` | numeric | Raw passthrough — **not** factor-converted (used as a filter value, not a regression factor) |
| 39 | `GilNK` | factor | Type-transformed |
| 40 | `ShaotAvodaBederechKlalNK` | numeric | Raw passthrough (source of `WorkHoursCont`) |
| 41 | `ChodsheiAvodaNK` | numeric | Raw passthrough |
| 42 | `MachozYishuvAvoda` | numeric | Raw passthrough |
| 43 | `DargatNayadut` | numeric | Raw passthrough (source of `WorksOutsideLocality`) |
| 44 | `TchunatAvodaShvuit` | numeric | Raw passthrough |
| 45 | `Muasak` | numeric | Raw passthrough (source of `Employed`) |
| 46 | `TchunatAvodaBederechKlal` | numeric | Raw passthrough |
| 47 | `TchunatAvodaShnatit` | numeric | Raw passthrough |
| 48 | `AnafKalkaliNK` | character | Raw passthrough |
| 49 | `MishkalSofi` | numeric | Raw passthrough (survey weight — unused anywhere) |
| 50 | `MishkalSofiAlafim` | numeric | Raw passthrough (survey weight — unused) |
| 51 | `MishkalShnati` | numeric | Raw passthrough (survey weight — unused) |
| 52 | `MishkalShnatiAlafim` | numeric | Raw passthrough (survey weight — unused) |
| 53 | `TchunatAvodaShvuitBZ` | numeric | Raw passthrough |
| 54 | `AnafKalkali_ISIC_R4_1` | character | Raw passthrough |
| 55 | `AnafKalkali_ISIC_R4_2` | character | Raw passthrough |
| 56 | `MishlachYad_ISCO_08_1` | character | Raw passthrough |
| 57 | `MishlachYad_ISCO_08_2` | numeric | Type-transformed (`as.numeric()` coerced; needed for a future WFH-exposure index) |
| 58 | `MishlachYadBenZug` | character | Raw passthrough |
| 59 | `MishlachYadNK` | character | Raw passthrough |
| 60 | `NayadutYishuvAvodaMechushav` | numeric | Raw passthrough |
| 61 | `SemelAnafKalkaliMechushav` | character | Raw passthrough |
| 62 | `SemelMishlachYadMechushav` | character | Raw passthrough |
| 63 | `MaamadAvodaMechushav` | numeric | Raw passthrough |
| 64 | `KamaChodashimAvadBashanaMechusha` | numeric | Raw passthrough |
| 65 | `AvadBaaretsMityaesh` | numeric | Raw passthrough |
| 66 | `HitchilLaavod` | numeric | Raw passthrough |
| 67 | `KamaYamim` | numeric | Raw passthrough |
| 68 | `ShaotIkarit` | numeric | Raw passthrough |
| 69 | `Siba35` | numeric | Raw passthrough |
| 70 | `YoterShaot` | numeric | Raw passthrough |
| 71 | `AvodaMeHaBayit` | numeric | Raw passthrough (source of `WFH`) |
| 72 | `AvadMeHaBayit` | numeric | Raw passthrough |
| 73 | `KamaShaot` | numeric | Raw passthrough |
| 74 | `HichlifAvoda` | numeric | Raw passthrough |
| 75 | `Mother` | integer | Derived |
| 76 | `Post` | integer | Derived |
| 77 | `Employed` | integer | Derived |
| 78 | `WFH` | numeric | Derived |
| 79 | `WorkHoursCont` | numeric | Derived |
| 80 | `BirthContinent` | factor | Derived |
| 81 | `WorksOutsideLocality` | integer | Derived |

**Schema-quality gap**: the ~65 raw-passthrough columns above have no explicit final-format contract — no renaming, no type normalization (numeric vs. character is whatever `read_csv()` guessed), no documented meaning beyond the original CBS codebook. Only the columns actually consumed downstream (§ below) have a defined contract. This is a real gap if the dataset is ever handed to someone without codebook access.

### Analysis-critical derived columns (exact contract)

| Column | Type | Values / levels | NA rate | Derivation |
|---|---|---|---|---|
| `Employed` | integer | `{0, 1}` | **0.000%** | `1` iff `Muasak == 1`, else `0` (unemployed + not-in-labor-force both → `0`) |
| `Mother` | integer | `{0, 1}` | **0.000%** | `1` iff `MisparYeladimAd17MB > 0` |
| `Post` | integer | `{0, 1}` | **0.000%** | `1` iff `ShnatSeker >= 2021` |
| `WFH` | numeric | `{0, 1}` | 63.938% | Only defined for `ShnatSeker >= 2021`; `NA` for all pre-2021 rows *by design* (question wasn't asked) |
| `WorkHoursCont` | numeric | `[0, 78.5]` | 0.001% (3 rows) | Bin-median lookup for `ShaotAvodaBederechKlalNK` codes 0–10; sample-median imputation for codes 11/12; `NA` for code 99 |
| `TeudaGvoha` | factor (6 levels) | `Below High School`, `High School (no matriculation)`, `Matriculation (Bagrut)`, `Post-secondary, non-academic`, `Academic Degree (BA/MA/PhD)`, `Other/No Certificate` | 2.135% | Collapsed from 11 raw codes; `NA` reserved for raw code 99 ("unknown") |
| `BirthContinent` | factor (6 levels) | `Africa`, `Asia`, `Europe`, `Israel`, `North America`, `Other` | 0.218% | Collapsed from 16 raw `SemelEretzLeda` codes; `NA` reserved for raw code 16 (ambiguous "unknown"/"other" in CBS's own codebook) |
| `WorksOutsideLocality` | integer | `{0, 1}` | 16.552% | From `DargatNayadut`: `1`→`0`, `2`–`7`→`1`, `0`/`8`/`NA`→`NA` |

Regression-control columns (`MatzavMishpachti`, `Dat`, `GilNK`, `MachozMegurim`, `MisparHorimYechidim`) are all `factor`, all **0.000% NA** (confirmed from the live data).

## Validation & Thresholds

### Hard-fail checks (pipeline should stop; none of these currently exist as code — see Implementation Roadmap)

| Check | Rule | Rationale |
|---|---|---|
| Sex filter invariant | `all(cleaned_df$Min == 2)` | `Min==2` is applied once at filter time; any other value surfacing downstream means the filter itself broke |
| Age filter invariant | `all(as.integer(as.character(cleaned_df$GilNK)) %in% 3:7)` | Same reasoning for the age-group filter |
| Year filter invariant | `all(cleaned_df$ShnatSeker %in% c(2017,2018,2019,2021,2022,2023))` | 2020 must never appear |
| `Employed`/`Mother`/`Post` NA rate | must equal exactly `0` | All three are `if_else()`-derived from always-defined inputs (`Muasak`, `MisparYeladimAd17MB`, `ShnatSeker`); *any* NA appearing means a regression in the derivation logic, not real-world missingness |
| Row count sanity | `nrow(cleaned_df) > 0` after each filter stage | Catches a filter that accidentally empties the frame |

### Soft-fail / warn thresholds (calibrated against the real observed rates above)

| Rule | Threshold | Basis |
|---|---|---|
| Any *regression control's* NA rate | warn if `> 5%` | None currently exceed this — `TeudaGvoha` at 2.1% is the highest control-level NA rate observed; a control crossing 5% would meaningfully shrink the regression's effective sample via `fixest`'s listwise deletion |
| Any *comparative-stats-only* variable's NA rate | warn if `> 70%` (informational only below that) | `WFH` at 63.9% is structurally expected (pre-2021 undefined by design), not a data-quality problem — the threshold should sit above it so `WFH` doesn't false-positive, while still catching a genuinely broken variable |
| `WorksOutsideLocality` NA rate | no warn below `~20%` | Its 16.6% NA is structurally expected (`DargatNayadut` codes 0/8 = didn't work / unknown), consistent across years |

### Null-handling logic, by variable class

1. **Derived binary outcomes** (`Employed`, `Mother`, `Post`) — never `NA` by construction; treat any `NA` as a hard failure, not data to impute.
2. **Category-grouping variables** (`TeudaGvoha`, `BirthContinent`) — `NA` is reserved *specifically* for the raw "unknown" code (99 / 16 respectively), never introduced by the grouping logic itself for a valid code. `fixest::feols()` silently listwise-deletes these rows; that's acceptable given the low rates above, but should be watched if raw data quality changes.
3. **Structurally-conditional variables** (`WFH`) — `NA` encodes "question not applicable this year," not missingness. Must never be imputed or treated as `0`.
4. **Mobility/commute variables** (`WorksOutsideLocality`) — `NA` covers both "didn't work" and "unknown," which are semantically different but not currently distinguished; flagged as a modeling simplification, not a defect.

### Schema-drift check (operationalizes the HLD's flagged column-order risk)

`data_processing.R` drops 7 column ranges positionally (`select(-(a:b))`), which depend on the raw CSV's column *order*, not names. A concrete check: assert, for each year's raw CSV independently, that the named boundary columns of every range (e.g. `RamatDat`, `BituachLeumi`, `Yeladim0_1Prat`, `Yeladim15_17Prat`, ...) occupy the same relative position they did in the 2019 file used to validate this pipeline. This doesn't exist as code today — see Implementation Roadmap.

## Core Function Signatures

### Existing (verified against current source)

```r
load_and_clean_data(folder_path: character(1)) -> tibble  # 81 cols, see Data Schema
# Side effects: reads every *.csv in folder_path; stop()s if folder_path doesn't exist.

run_comparative_stats(cleaned_df: tibble) ->
  invisible(list(
    missing_pct      = tibble,   # variable, pct_missing
    emp_by_mother    = tibble,   # Mother, emp_rate, n
    mobility_by_year = tibble,   # ShnatSeker, Mother, pct_outside, n, MotherLabel
    plots            = list(mobility = ggplot)
  ))
# Side effects: message()/print()s every intermediate table; print()s one ggplot.

basic_reg(cleaned_data: tibble) ->
  invisible(list(
    table  = etable_df,
    models = list(employed = fixest)   # Employed ~ Mother + Post + Mother:Post + controls, cluster = ~IDPUF
  ))
# controls = c("MatzavMishpachti","Dat","GilNK","MachozMegurim","TeudaGvoha")
# Side effects: print()s the etable.

basic_reg_comp(cleaned_data: tibble) ->
  invisible(list(
    table  = etable_df,
    models = list(employed = fixest, employed_muasak = fixest)
  ))
# Same formula as basic_reg(), fit once on the full sample and once on filter(!is.na(Muasak)).
# Not called from main.R by default.

employment_by_child_age(cleaned_df: tibble) ->
  invisible(list(
    emp_raw       = tibble,   # ChildAgeBin, emp_rate, n
    emp_by_period = tibble,   # ChildAgeBin, Post, emp_rate, n, Period
    model         = fixest,   # Employed ~ ChildAgeBin + controls, cluster = ~IDPUF
    plots         = list(raw = ggplot, period = ggplot, adjusted = ggplot)
  ))
# Side effects: message()/print()s tables; print()s 3 ggplots.

run_diagnostics(cleaned_df: tibble) ->
  invisible(list(
    did_table      = tibble,   # Mother, Post, emp_rate, n
    na_summary     = tibble,   # 1-row wide NA counts for regression variables
    miss_pattern   = tibble,   # emp_missing, pct_mother, mean_age, n
    pretrend_model = fixest    # Employed ~ Mother + i(ShnatSeker, Mother, ref=2019) + controls
  ))
# Side effects: dev.new()/iplot() for the event-study plot (needs a null-device wrapper in any
# non-interactive context — see TESTING_BLUEPRINT.md).
```

### Proposed (to close the HLD's gaps — do not yet exist)

```r
run_intensive_margin_reg(cleaned_df: tibble, controls: character = DEFAULT_CONTROLS) ->
  invisible(list(table = etable_df, models = list(hours = fixest)))
# WorkHoursCont ~ Mother + Post + Mother:Post + controls, cluster = ~IDPUF, filtered to Employed==1
# (hours are only meaningful conditional on employment).

build_wfh_exposure_index(cleaned_df: tibble,
                          isco_col: character(1) = "MishlachYad_ISCO_08_2",
                          wfh_col: character(1) = "WFH",
                          ref_year: numeric(1) = 2021) -> tibble
# Returns one row per occupation code: occupation_code, wfh_exposure (share of that occupation's
# workers with WFH==1 in ref_year). NOTE: the research doc specifies the 2020 WFH variable as the
# exposure anchor, but 2020 is excluded from this project's sample entirely (transitional-year
# exclusion) — ref_year defaults to 2021 pending a decision on whether a separate 2020-only extract
# is pulled just for this index (see HLD Gap Analysis).

run_ddd_regression(cleaned_df: tibble, exposure_index: tibble,
                    controls: character = DEFAULT_CONTROLS) ->
  invisible(list(table = etable_df, models = list(ddd = fixest, mechanism = lm)))
# Two models: (1) Employed ~ Mother*Post*WFH_Exposure + controls (triple interaction);
# (2) the second-stage beta_j ~ gamma_0 + gamma_1 * WFH_Exposure_j mechanism regression
# from occupation-level DiD estimates.

load_and_clean_data(folder_path: character(1),
                     sex_filter: character = c("women", "men")) -> tibble
# BREAKING CHANGE to the existing signature: sex_filter defaults to "women" to preserve current
# behavior (Min==2) for every existing caller; "men" selects Min==1 for the Gender Placebo Test.
```

## HLD Gap Analysis

| Gap (from `docs/HLD.md` §4.2) | Exact missing piece | Blocking dependency | Effort/risk |
|---|---|---|---|
| Intensive-margin regression | `run_intensive_margin_reg()` function | None — `WorkHoursCont` already exists and is clean (0.001% NA) | Low. Straightforward `fixest` call, same pattern as `basic_reg()`. |
| WFH-Exposure Index | `build_wfh_exposure_index()` function; occupation-level aggregation | `MishlachYad_ISCO_08_2` is parsed but nothing aggregates it; **and** the research doc's specified anchor year (2020) is excluded from this project's sample entirely, so the index can't be built from `cleaned_df` as currently filtered without a decision on data source | Medium. Needs either a separate 2020 extract or a documented deviation to use 2021 as the exposure-anchor year instead. |
| DDD mechanism regression | `run_ddd_regression()` function | Depends entirely on the WFH-Exposure Index above | Medium, gated on the item above. |
| Gender Placebo Test | fathers-vs-childless-men variant of `basic_reg()`; a way to get men into `cleaned_df` at all | `data_processing.R`'s `Min==2` filter is unconditional — no parameter exists to select men. Every downstream file's variable naming/comments also implicitly assume "women" (e.g. `Mother` is defined the same way regardless of sex, which is actually fine, but district/education/marital controls were never checked for a male subsample's category sparsity) | Medium-high. Needs the `sex_filter` signature change above, then a re-check of every control's category sizes within the male subsample (Priority-3 concern: `Validation & Thresholds` §"soft-fail" logic should be re-run against the men-only sample before trusting the placebo model). |
| Continuous `Age`/`Age²` controls | A continuous-age column | **Confirmed absent from the raw CBS extract entirely** — no `Gil` (age) column exists beyond age-*group* codes (`GilNK`) and child-age codes; no birth-year column (`ShnatLeda` or equivalent) exists either, so age can't even be back-calculated | This is a **data-availability gap, not a coding gap**. Requires either requesting a wider CBS extract that includes continuous age or birth year, or formally dropping this control from the Part 4 §2 spec in favor of the categorical `GilNK` already in use (which is what Part 3 §3's advisor feedback actually called for). |
| Persisted output/export layer | Nothing writes a table or plot to disk | None technical — just not built | Low effort, but pulls in a new dependency (see Roadmap). |
| Validation/threshold checks (this document's own §2) | No guard function exists anywhere in the codebase today | None | Low effort, pure `tidyverse`/base R, no new dependency. |
| Schema-drift check (this document's own §2) | No guard function exists | None | Low effort, but needs at least 2 years' raw headers to test against meaningfully. |

## Implementation Roadmap

Prioritized checklist, each item tagged with the concrete tool/library it needs:

1. **Validation/threshold guard function** — base R + `tidyverse`, no new dependency. Do this first: it protects every subsequent item from silently building on broken data.
2. **Schema-drift check** — base R (`setdiff`/column-position comparison across raw CSV headers), no new dependency.
3. **Intensive-margin regression** (`run_intensive_margin_reg()`) — `fixest`, no new dependency. Highest-value item with zero blocking dependencies.
4. **`controls` de-duplication** (referenced in `TESTING_BLUEPRINT.md`, relevant here too since every new regression function above needs the same list) — no new dependency; a shared constant sourced once.
5. **WFH-Exposure Index construction** — `tidyverse`; blocked pending a decision on the 2020-anchor-year data question above.
6. **DDD mechanism regression** — `fixest`; blocked on #5.
7. **Gender Placebo Test** — `fixest` + the `load_and_clean_data()` signature change; medium effort, no new dependency, but touches the most files (every control's category-sparsity needs re-validation for the male subsample).
8. **Age/Age² controls** — **blocked on data availability**, not an engineering task. Escalate to the research team to either request a wider CBS extract or formally drop this from the spec.
9. **Persisted output/export layer** — new dependency territory (e.g. `gt`/`officer`/`rmarkdown` for tables and a written report). Explicitly deferred: outside the project's current minimal (`tidyverse` + `fixest`) dependency footprint, lowest priority relative to the modeling gaps above.

## Verification

This document's Data Schema and Validation sections were generated by loading the actual `cleaned_df.rds` cache (372,741 × 81, produced by the current `data_processing.R`) and dumping real column names, types, factor levels, and NA rates via `Rscript` — not reconstructed from reading source code. The Age/Age² data-availability claim was confirmed by grepping every raw CSV header for age- and birth-year-related column names before writing it down as absent. Every function signature under "Existing" was cross-checked against the current `.R` files.
