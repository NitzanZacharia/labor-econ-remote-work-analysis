# Low-Level Design: Motherhood Penalty / WFH Analysis Pipeline

Derived from [`docs/HLD.md`](HLD.md) and the actual current state of the repository. The original 81-column table below was pulled directly from a real cached `cleaned_df.rds` (372,741 rows × 81 columns) as it stood at the time — not reconstructed from reading code — see the Verification note at the end. `data_processing.R` has since grown 6 more derived columns (`WFH_RefWeek`, `WFH_Hours`, `WFH_Share`, `WFH_Arrangement`, `ISCO_masked`, `ISCO1`), documented in a follow-on subsection below the original table; those 6 were reconciled directly from the current code, **not** from a fresh live pull, so their exact final column position (as opposed to their existence, type, and derivation) is not independently re-verified the way rows 1-81 were. The dataset is currently **372,741 rows × 87 columns**.

## Data Schema

`cleaned_df` (the output of `load_and_clean_data()`) is a flat tibble, currently 372,741 rows × 87 columns (81 as of the original live pull below, plus 6 documented in the follow-on subsection). Columns fall into three classes:

- **Derived (new)** — created by `data_processing.R`, not present in the raw CBS extract.
- **Type-transformed** — a raw CBS column, converted to `factor` or recoded/grouped in place (same column name, new representation).
- **Raw passthrough** — an untouched raw CBS column (Hebrew-named, numeric or character), surviving the drop step unchanged.

### Full column list (original 81-column live pull)

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
| 57 | `MishlachYad_ISCO_08_2` | numeric | Type-transformed (`as.numeric()` coerced; join key for the WFH-exposure index and DDD regressions — see the follow-on subsection below for `ISCO_masked`/`ISCO1`, added alongside it since this pull) |
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
| 72 | `AvadMeHaBayit` | numeric | Raw passthrough (source of `WFH_RefWeek`) |
| 73 | `KamaShaot` | numeric | Raw passthrough (source of `WFH_Hours` / `WFH_Share`) |
| 74 | `HichlifAvoda` | numeric | Raw passthrough |
| 75 | `Mother` | integer | Derived |
| 76 | `Post` | integer | Derived |
| 77 | `Employed` | integer | Derived |
| 78 | `WFH` | numeric | Derived |
| 79 | `WorkHoursCont` | numeric | Derived |
| 80 | `BirthContinent` | factor | Derived |
| 81 | `WorksOutsideLocality` | integer | Derived |

**Schema-quality gap**: the ~65 raw-passthrough columns above have no explicit final-format contract — no renaming, no type normalization (numeric vs. character is whatever `read_csv()` guessed), no documented meaning beyond the original CBS codebook. Only the columns actually consumed downstream (§ below) have a defined contract. This is a real gap if the dataset is ever handed to someone without codebook access.

### Columns added since the original 81-column pull

Reconciled directly from the current `data_processing.R` (not a fresh live pull — see the note at the top of this document). All 6 are genuinely new columns (not present in the original pull), so they sit after column 81 in creation order; their exact final index is not independently re-verified.

| Column | Type | Class | Derivation |
|---|---|---|---|
| `WFH_RefWeek` | numeric | Derived | Reference-week WFH behaviour, from `AvadMeHaBayit` (same 1/2/9→1/0/NA mapping as `WFH`). Created immediately after `WFH` in `data_processing.R`'s WFH block. |
| `WFH_Hours` | numeric | Derived | Hours worked from home in the reference week, from `KamaShaot` (only defined when `WFH_RefWeek == 1`). |
| `WFH_Share` | numeric | Derived | `WFH_Hours / ShaotAvodaLeMaase`, capped at 1. |
| `WFH_Arrangement` | factor (3 levels) | Derived | Binned from `WFH_Share`: On-site / Hybrid / Fully remote. |
| `ISCO_masked` | logical | Derived | `TRUE` where the raw `MishlachYad_ISCO_08_2` held a CBS disclosure mask (`XX`, `7X`, …) rather than a numeric code. Created in the ISCO block, immediately after column 57's type transform. |
| `ISCO1` | numeric | Derived | 1-digit ISCO-08 major group, recovered from the first character of the raw code (survives partial masking, e.g. `7X` → `7`). |

See the "Analysis-critical derived columns" table below for each column's exact NA-rate contract and derivation logic.

### Analysis-critical derived columns (exact contract)

| Column | Type | Values / levels | NA rate | Derivation |
|---|---|---|---|---|
| `Employed` | integer | `{0, 1}` | **0.000%** | `1` iff `Muasak == 1`, else `0` (unemployed + not-in-labor-force both → `0`) |
| `Mother` | integer | `{0, 1}` | **0.000%** | `1` iff `MisparYeladimAd17MB > 0` |
| `Post` | integer | `{0, 1}` | **0.000%** | `1` iff `ShnatSeker >= 2021` |
| `WFH` | numeric | `{0, 1}` | 64.726% | Usual work location, from `AvodaMeHaBayit`: `1`→`1`, `2`→`0`, `9` ("unknown")→**`NA`**, blank→`NA`. Only defined for `ShnatSeker >= 2021`; `NA` for all pre-2021 rows *by design* (question wasn't asked). The NA rate rose from 63.938% when code `9` stopped being silently recoded as `0` |
| `WFH_RefWeek` | numeric | `{0, 1}` | 68.629% | Reference-week behaviour, from `AvadMeHaBayit`, same code mapping. Asked only of the employed who worked that week (`AvadBeshavua == 1`), so the employed-but-absent are `NA`, not `0`. Disagrees with `WFH` in both directions — 6,182 rows in 2021 answer "no" to usual and "yes" to reference-week |
| `WFH_Hours` | numeric | `[0, 84]` | 68.648% | Hours worked from home in the reference week, from `KamaShaot` (asked only when `WFH_RefWeek == 1`). `0` when `WFH_RefWeek == 0`; `NA` when either hour item carries a CBS code in the 90s ("irregular"/"unknown") |
| `WFH_Share` | numeric | `[0, 1]` | 68.659% | `WFH_Hours / ShaotAvodaLeMaase`, capped at 1. `0` when `WFH_RefWeek == 0`; `NA` whenever `WFH_RefWeek` is `NA` or either hour item is a 90s code. Verified `KamaShaot <= ShaotAvodaLeMaase` in 18,619/18,619 valid 2021 cases |
| `WFH_Arrangement` | factor (3 levels) | `On-site` (91,480), `Hybrid` (15,685), `Fully remote` (9,655) | 68.659% | Binned from `WFH_Share`: `0` → On-site, `(0, 0.9)` → Hybrid, `>= 0.9` → Fully remote |
| `ISCO_masked` | logical | `{TRUE, FALSE}` | **0.000%** | `TRUE` where the raw `MishlachYad_ISCO_08_2` held a CBS disclosure mask (`XX`, `7X`, …) rather than a code. 2.365% of the analysis sample; 7.5% of all employed in the raw 2021 file, since masking concentrates in thin occupation cells |
| `ISCO1` | numeric | `[1, 9]` | 18.052% | 1-digit ISCO-08 major group, recovered from the first character of the raw code so partially-masked values (`7X` → `7`) survive. Non-`NA` for 231 employed 2021 rows that `MishlachYad_ISCO_08_2` loses entirely |
| `WorkHoursCont` | numeric | `[0, 78.5]` | 0.001% (3 rows) | Bin-median lookup for `ShaotAvodaBederechKlalNK` codes 0–10; codes 11/12 imputed from the median of the matching bin range, computed separately within each `Post` period (not pooled across 2017–2023 — pooling would blend the pre/post hour distributions and dampen any real period-specific intensity shift); `NA` for code 99 |
| `TeudaGvoha` | factor (6 levels) | `Below High School`, `High School (no matriculation)`, `Matriculation (Bagrut)`, `Post-secondary, non-academic`, `Academic Degree (BA/MA/PhD)`, `Other/No Certificate` | 2.135% | Collapsed from 11 raw codes; `NA` reserved for raw code 99 ("unknown") |
| `BirthContinent` | factor (6 levels) | `Africa`, `Asia`, `Europe`, `Israel`, `North America`, `Other` | 0.218% | Collapsed from 16 raw `SemelEretzLeda` codes; `NA` reserved for raw code 16 (ambiguous "unknown"/"other" in CBS's own codebook) |
| `WorksOutsideLocality` | integer | `{0, 1}` | 16.552% | From `DargatNayadut`: `1`→`0`, `2`–`7`→`1`, `0`/`8`/`NA`→`NA` |

Regression-control columns (`MatzavMishpachti`, `Dat`, `GilNK`, `MachozMegurim`, `MisparHorimYechidim`) are all `factor`, all **0.000% NA** (confirmed from the live data).

## Validation & Thresholds

### Hard-fail checks (pipeline should stop; implemented in `validation.R`'s `validate_cleaned_df()`)

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

### Schema-drift check (implemented in `validation.R`'s `check_schema_drift()`)

`data_processing.R` drops column ranges positionally (`select(-(a:b))`), which depend on the raw CSV's column *order*, not names — originally 7 ranges, now 5 (2 were converted to explicit `any_of()`-based name drops after `2017_Data.csv` turned out to lack all 4 of those boundary columns entirely, which made the positional check fail on a file that was never going to contain them in the first place). `check_schema_drift(folder_path)` asserts, for every year's raw CSV independently, that the named boundary columns of each of the 5 remaining ranges (`Yeladim0_1Prat`/`Yeladim15_17Prat`, `MisparHachlafa`/`YachasKirvaNK`, `MisparNefashotGilAvodaV2007`/`MisparPrat`, `ChipusAvodaSherutTaasuka`/`ChipusAvodaOfenAcher`, `RamatDat`/`BituachLeumi`) occupy the same relative column position across every file, throwing a clear error rather than silently dropping the wrong columns if a future CBS release reorders them. Called from `main.R` before every fresh (non-cached) `load_and_clean_data()` run.

## Core Function Signatures

### Existing (verified against current source; all previously-"Proposed" functions in this section have since been built)

```r
# ── data_processing.R ──────────────────────────────────────────────────────
load_and_clean_data(folder_path: character(1),
                     sex_filter: character = c("women", "men")) -> tibble  # 87 cols, see Data Schema
# sex_filter defaults to "women" (Min==2); "men" selects Min==1 (the Gender Placebo Test).
# Side effects: reads every *.csv in folder_path; stop()s if folder_path doesn't exist.

# ── validation.R ────────────────────────────────────────────────────────────
validate_cleaned_df(cleaned_df: tibble, sex_filter: character = c("women", "men")) -> invisible(TRUE)
# stop()s on hard-fail checks (see Validation & Thresholds); warning()s on soft-fail thresholds.

check_schema_drift(folder_path: character(1)) -> invisible(TRUE)
# stop()s if any of the 5 positional-range boundary columns has moved between yearly CSVs.

check_idpuf_panel_structure(cleaned_df: tibble) ->
  invisible(list(
    n_idpuf = integer(1), multi_year_n = integer(1), cross_period_n = integer(1),
    idpuf_years = tibble, idpuf_periods = tibble
  ))
# Reporting-only: how much IDPUF repeats across ShnatSeker years / the Post==0-vs-1 divide.

check_wfh_refweek_avadbeshavua(cleaned_df: tibble) ->
  invisible(list(available = logical(1), n = integer(1),
                  consistent = integer(1), inconsistent = integer(1), indeterminate = integer(1)))
# Verifies (doesn't assume) that WFH_RefWeek's blank-AvadMeHaBayit rows coincide with
# AvadBeshavua != 1, among employed Post==1 rows. Degrades to available=FALSE if AvadBeshavua
# isn't present in cleaned_df. warning()s if any row contradicts the claim.

# ── comparative_statistics.R ────────────────────────────────────────────────
run_comparative_stats(cleaned_df: tibble) ->
  invisible(list(
    missing_pct = tibble, emp_by_mother = tibble, mobility_by_year = tibble,
    plots = list(mobility = ggplot)
  ))

# ── basic_regression.R / basic_reg_compared_data.R ──────────────────────────
basic_reg(cleaned_data: tibble) ->
  invisible(list(table = etable_df, models = list(employed = fixest)))
# Employed ~ Mother + Post + Mother:Post + DEFAULT_CONTROLS, cluster = ~IDPUF.

basic_reg_comp(cleaned_data: tibble) ->
  invisible(list(table = etable_df, models = list(employed = fixest, employed_muasak = fixest)))
# Same formula as basic_reg(), fit on the full sample and on filter(!is.na(Muasak)).
# Not called from main.R by default.

# ── intensive_margin_regression.R / intensive_margin_lee_bounds.R ──────────
run_intensive_margin_reg(cleaned_df: tibble, controls: character = DEFAULT_CONTROLS) ->
  invisible(list(table = etable_df, models = list(hours = fixest)))
# WorkHoursCont ~ Mother + Post + Mother:Post + controls, cluster = ~IDPUF, Employed==1 only.

run_intensive_margin_lee_bounds(cleaned_df: tibble, controls: character = DEFAULT_CONTROLS) ->
  invisible(list(
    table = tibble,   # bound (lower/point/upper), mother_post_coef
    models = list(point = fixest, lower = fixest, upper = fixest),
    diagnostics = list(selection_rates = tibble, s11_counterfactual = numeric(1),
                        excess_selection = logical(1), trim_prop = numeric(1), n_trimmed = integer(1))
  ))
# Lee (2009) trimming bounds for run_intensive_margin_reg()'s Employed==1 selection risk —
# see docs/decisions/intensive-margin-lee-bounds.md.

# ── employment_by_child_age.R ────────────────────────────────────────────────
employment_by_child_age(cleaned_df: tibble) ->
  invisible(list(
    emp_raw = tibble, emp_by_period = tibble, model = fixest,
    plots = list(raw = ggplot, period = ggplot, adjusted = ggplot)
  ))

# ── Diagnostics.R ─────────────────────────────────────────────────────────
run_diagnostics(cleaned_df: tibble) ->
  invisible(list(
    did_table = tibble, na_summary = tibble, miss_pattern = tibble,
    pretrend_table = etable_df, pretrend_model = fixest
    # Employed ~ Mother + i(ShnatSeker,ref=2019) + i(ShnatSeker,Mother,ref=2019) + controls
  ))
# Side effects: iplot(reg_pretrend, i.select = 2, ...) draws to whatever device is active (no
# dev.new()) -- needs an explicit device (main.R) or a null-device wrapper (tests) around the call.

# ── gender_placebo.R ─────────────────────────────────────────────────────────
run_gender_placebo(folder_path: character(1), cleaned_women: tibble = NULL,
                    exposure_calibrated: tibble = NULL,
                    exposure_csv_path: character(1) = "data/israeli_cbs_wfh_2digit.csv") ->
  invisible(list(cleaned_men = tibble, result = list(...), ddd_placebo = list(...) | NULL))
  # result is basic_reg()'s own return; ddd_placebo is run_gender_ddd_placebo()'s return (NULL if
  # no exposure_calibrated could be obtained/supplied).
run_gender_ddd_placebo(cleaned_men: tibble, exposure_calibrated: tibble,
                        controls: character = DEFAULT_CONTROLS) ->
  list(exposure_cells_men = tibble, models = list(additive = fixest | NULL, fe = fixest | NULL))
# Not called from main.R by default. Both feols() calls cluster on the (GilNK, TeudaGvoha,
# MachozMegurim) cell, matching main.R's primary DDD -- WFH_Exposure is cell-constant here too.

# ── wfh_exposure_index.R / wfh_exposure_cells.R / isco_masking_diagnostics.R /
#    ddd_collinearity_diagnostics.R ────────────────────────────────────────
build_wfh_exposure_index(cleaned_df: tibble,
                          isco_col: character(1) = "MishlachYad_ISCO_08_2",
                          wfh_col: character(1) = "WFH",
                          ref_year: numeric = 2021,
                          weight_col: character(1) = NULL, min_n: numeric(1) = 0) -> tibble
# occupation_code, wfh_exposure, n. ref_year anchored to 2021, not the research doc's literal 2020
# (excluded from this project's sample) -- see docs/decisions/checkpoint6-wfh-anchor-year.md.

build_exposure_isco2(path: character(1) = "data/israeli_cbs_wfh_2digit.csv") -> tibble  # ISCO2, tele_ext
# Reads the external Dingel & Neiman teleworkability score. `path` exists so callers/tests can
# point elsewhere; the default file isn't present in every environment.

calibrate_isco_exposure(cleaned_df: tibble, exposure_isco2: tibble, wfh_col: character(1) = "WFH",
                         ref_year: numeric = c(2022, 2023), gap_threshold: numeric(1) = 0.5,
                         conf_level: numeric(1) = 0.95) -> tibble
# ISCO2, tele_ext, n, realized_wfh, se_clustered, se_na_reason, gap, margin, swap,
# wfh_exposure_calibrated. One-sided cluster-robust test of whether realized WFH exceeds the
# external score by more than gap_threshold, at conf_level confidence — see
# docs/decisions/calibrated-exposure-and-cell-ddd.md.

build_exposure_cells(raw_all: tibble, exposure_isco2: tibble,
                      cell_vars: character = c("Min", "GilNK", "TeudaGvoha", "MachozMegurim")) -> tibble
# Pre-period (2017-2019) shift-share exposure by demographic cell, weighted by MishkalSofi. The
# primary DDD's exposure regressor -- unlike the other 3 measures, defined for non-employed rows too.

check_isco_masking_sensitivity(cleaned_df: tibble, wfh_col: character(1) = "WFH",
                                ref_year: numeric = c(2022, 2023)) ->
  invisible(list(by_group = tibble, comparison_wide = tibble, model = fixest))
# Proxy check: realized WFH, masked vs. unmasked, within each ISCO1 major group.

check_spec1_collinearity(ddd_df: tibble, cell_fe_vars: character, controls: character) ->
  invisible(list(r2_wfh_exposure_on_cells = numeric(1), vif_wfh_exposure = numeric(1),
                  condition_number = numeric(1)))
# Runtime collinearity diagnostic for the primary DDD's Spec 1. Base R only (lm(), kappa()) --
# deliberately no car dependency.

check_wfh_first_stage_relevance(ddd_df: tibble, controls: character = DEFAULT_CONTROLS) ->
  invisible(list(level_reg = fixest, dynamic_reg = fixest, table = etable))
# First-stage relevance check: does WFH_Exposure predict realized WFH_RefWeek (Post==1 only)? See
# docs/decisions/null-vs-power-audit.md.

compute_ddd_mde(model: fixest, coef_name: character(1) = "Mother:Post:WFH_Exposure",
                 sig_level: numeric(1) = 0.05, power: numeric(1) = 0.8,
                 baseline_rate: numeric(1) = NULL) ->
  invisible(list(coef_name, point_estimate, se, sig_level, power, mde, within_mde))
# Closed-form minimum detectable effect for a fitted model's coefficient. Base R only (qnorm()) --
# see docs/decisions/null-vs-power-audit.md.

# ── ddd_regression.R ──────────────────────────────────────────────────────
run_ddd_regression(cleaned_df: tibble, exposure_index: tibble,
                    controls: character = DEFAULT_CONTROLS) ->
  invisible(list(
    table = etable_df, models = list(ddd = fixest, mechanism = lm), mechanism_data = tibble,
    dropped_occupations = list(data = tibble, n_dropped = integer(1),
                                mean_exposure_dropped = numeric(1), mean_exposure_retained = numeric(1))
  ))
# Model 1: Employed ~ Mother*Post*WFH_Exposure + controls (triple interaction).
# Model 2: precision-weighted (1/se_j^2) beta_j ~ gamma_0 + gamma_1*WFH_Exposure_j, from
# occupation-stratified basic_reg() runs.

# ── robustness/balance_test.R / age_balance_robustness.R / pretrend_wald_test.R ─────────────
run_balance_test(cleaned_df: tibble, controls: character = DEFAULT_CONTROLS,
                  exposure_cells: tibble = NULL, exposure_calibrated: tibble = NULL,
                  exposure_csv_path: character(1) = "data/israeli_cbs_wfh_2digit.csv") ->
  invisible(list(pre_df = tibble, gilnk_balance = tibble, gilnk_ttests = tibble,
                  cat_distributions = tibble, cat_chisq = tibble))
# Pre-period (ShnatSeker < 2020) covariate balance, Mother vs. non-Mother, by WFH_Exposure
# quartile. pre_df is row-level -- excluded from export_all_results() (disclosure risk).

diagnose_gilnk_by_quartile(cleaned_df: tibble, exposure_cells: tibble) ->
  invisible(list(gap_by_quartile = tibble, breaks = numeric(5), pre_df = tibble))
# gap_by_quartile: mean_GilNK_Mother0/1, gap_Mother1_minus_0, t_stat, p_value, n, per quartile.
# Verified against real data 2026-09-09: gap is largest in Q1 (~-0.8 GilNK units, t~-81) and
# shrinks/reverses by Q4 -- see docs/decisions/age-balance-robustness-chain.md.

run_ddd_age_interacted(cleaned_df: tibble, exposure_cells: tibble,
                        controls: character = DEFAULT_CONTROLS) ->
  invisible(list(additive = fixest, fe = fixest))
# main.R's primary DDD formulas + Mother:GilNK. Comparison spec, not a main.R replacement.

build_gilnk_rake_weights(cleaned_df: tibble, exposure_cells: tibble) ->
  list(weights = tibble(WFH_Exposure_Q, Mother, GilNK, rake_weight), breaks = numeric(5))
run_ddd_reweighted(cleaned_df: tibble, exposure_cells: tibble,
                    controls: character = DEFAULT_CONTROLS, rake: list = NULL) ->
  invisible(list(rake = list(...), additive = fixest, fe = fixest))
# Pre-period GilNK-raking weights (by WFH_Exposure quartile x Mother), applied via weights=
# to the full-period regression. Comparison spec, not a main.R replacement.

run_pretrend_joint_test(pretrend_model: fixest) -> invisible(wald_result)
# Joint Wald test, H0: Diagnostics.R's pre-2020 Mother:year interactions are jointly zero.

# All four wired into main.R behind RUN_AGE_BALANCE_ROBUSTNESS (default FALSE) -- see
# docs/decisions/age-balance-robustness-chain.md. robustness/phase2_robustness.R
# (run_ddd_twoway_cluster(), run_ddd_education_checks(), run_ddd_weights_check()) exists but is
# NOT wired in: run_ddd_weights_check() applies MishkalSofi as a feols() weight, which needs
# explicit user sign-off per CLAUDE.md before any run uses it, not just before committing output.

# ── israeli_market_mismatch.R ────────────────────────────────────────────────
check_market_mismatch(cleaned_df: tibble, exposure_path: character(1) = "data/israeli_cbs_wfh_2digit.csv",
                       ...) -> tibble
# calibrate_isco_exposure()'s output plus israel_vs_us_gap, abs_mismatch; sorted desc(abs_mismatch).
# Descriptive-only; not sourced by main.R (invoked via run_mismatch.R).

# ── export_results.R ──────────────────────────────────────────────────────
export_all_results(results_list: list, output_dir: character(1) = "outputs") -> invisible(character)
# Recursively walks results_list: data frames -> CSV, ggplots -> PNG, fixest/lm objects skipped.
# Returns the vector of file paths written.
```

## HLD Gap Analysis

**Status: closed.** Every gap this table originally tracked (validation/threshold checks, the schema-drift check, the intensive-margin regression, the WFH-exposure index, the DDD mechanism regression, the Gender Placebo Test, and the persisted output/export layer) is now implemented — see `docs/HLD.md` §4.1 for the full current file list, and `docs/ROADMAP.md` for the checkpoint history. The one item below that was ever a genuine data-availability blocker (not an engineering gap) was resolved as a recorded decision rather than closed by acquiring new data:

| Original gap | Resolution |
|---|---|
| Continuous `Age`/`Age²` controls — confirmed absent from the raw CBS extract entirely (no `Gil`/`ShnatLeda`-equivalent column exists) | **Decided, not built**: `docs/decisions/checkpoint8-age-age2-controls.md` formally replaces this control with the categorical `GilNK` already in use everywhere — matching Part 3 §3's own advisor feedback for categorical dummies. Not an open gap. |

Work has since gone **beyond** what this table or the original roadmap scoped — a statistically-calibrated exposure measure and a cell-based primary DDD (`wfh_exposure_cells.R`, `docs/decisions/calibrated-exposure-and-cell-ddd.md`), a Lee (2009) selection-bounds correction for the intensive margin (`docs/decisions/intensive-margin-lee-bounds.md`), and several runtime diagnostics (`validation.R`'s `check_idpuf_panel_structure()`/`check_wfh_refweek_avadbeshavua()`, `isco_masking_diagnostics.R`, `ddd_collinearity_diagnostics.R`). None of these are "gaps" in the sense this table originally meant (missing pieces of the research-doc spec) — they're refinements layered on top of a complete spec, each with its own decision memo. See `docs/HLD.md` §4.2 for the current list of documented limitations and deliberate decisions (survey weights not applied, Lee bounds' one-directional limitation, etc.) — that's the accurate analogue of this section today.

## Implementation Roadmap

**Status: complete.** The 9-step build order this section originally specified (validation guard → schema-drift check → intensive-margin regression → controls de-duplication → WFH-exposure index → DDD mechanism regression → Gender Placebo Test → Age/Age² decision → export layer) matches `docs/ROADMAP.md`'s 10 checkpoints and all of it has shipped. For what's been built since, see `docs/HLD.md` §4.1's file table and the decision memos in `docs/decisions/`. There is currently no pending roadmap item — new work should get its own checkpoint entry or decision memo (per `CLAUDE.md`'s convention) rather than being implemented ad hoc, so a future reader can find the rationale the way this section once made possible for the original 9.

## Verification

The original 81-column Data Schema and Validation sections were generated by loading the actual `cleaned_df.rds` cache (372,741 × 81, as it stood at the time) and dumping real column names, types, factor levels, and NA rates via `Rscript` — not reconstructed from reading source code. The Age/Age² data-availability claim was confirmed by grepping every raw CSV header for age- and birth-year-related column names before writing it down as absent — this remains true; it's the reason `docs/decisions/checkpoint8-age-age2-controls.md` exists. The 6 columns added since (see "Columns added since the original 81-column pull") and the "Core Function Signatures" section were reconciled directly against the current `.R` files in this repo, not from a fresh `Rscript` data pull — flagged wherever that distinction matters. `Validation & Thresholds`' hard/soft-fail checks and the schema-drift check are no longer a design spec; both are implemented in `validation.R` and can be read directly from source.
