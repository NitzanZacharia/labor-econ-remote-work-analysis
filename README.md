# labor-econ-remote-work-analysis

**The Impact of Remote Work on the "Motherhood Penalty": An Empirical Analysis of the Israeli Labor Market in the Post-COVID Era.**

Empirical analysis using Israeli Central Bureau of Statistics (CBS) Labor Force Survey microdata to test whether the post-COVID shift to remote work altered the motherhood penalty in the Israeli labor market.

## Background

**Motivation.** Israel combines high labor productivity with birth rates that are exceptionally high compared to the rest of the OECD, so changes in the motherhood penalty carry outsized economic weight. The findings are intended to inform local policy debates on gender equality, maternity leave, and flexible work arrangements.

**The motherhood penalty.** A well-documented negative effect of childbirth on women's wages and employment, opening a persistent gap between mothers and both men and childless women (long-term wage penalties of roughly 20–40% in the literature). It's driven by mothers shifting to part-time/"mommy track" roles, an unequal household/childcare burden, and "commitment bias" discrimination by employers who perceive mothers as less committed.
- Correll et al. (2007): mothers face wage/hiring discrimination from a "less committed" stereotype; fathers see the opposite — a wage premium.
- Kleven et al. (2019, Denmark): first childbirth causes a ~20% long-term income decline for women, via reduced hours, labor-market exit, or a shift to lower-paying family-friendly jobs.
- Kleven et al. (2019, cross-country): the penalty is universal but its severity tracks cultural/gender norms, steepest where mothers are expected to stay home.
- Harrington et al. (2025): rising remote work is shrinking the penalty — higher employment for mothers in demanding professions, less post-birth dropout, easier work/parenting integration.

**Why remote work might change it.** The pandemic pushed work-from-home from ~5% to ~25–30% of workdays. This could narrow the penalty (less commute friction, more schedule flexibility, reduced stigma around physical availability) or widen it (lower visibility, slower advancement, new remote-specific stigma) — which is why this is an empirical question rather than an assumed direction.

## Research design

The core analysis is a mother/non-mother × pre/post-2021 difference-in-differences design, using the COVID-era shift toward remote work as the "post" treatment period:

$$Y_{it} = \beta_0 + \beta_1 \cdot \text{Mother}_i + \beta_2 \cdot \text{Post}_t + \beta_3 \cdot (\text{Mother}_i \times \text{Post}_t) + X'_{it}\gamma + \varepsilon_{it}$$

- **Y**: employment (extensive margin) and weekly work hours (intensive margin).
- **Mother**: 1 for women with a child under 17 (treatment group); 0 for childless women (control group).
- **Post**: 1 for 2021–2023 (post-shift), 0 for 2017–2019 (baseline); 2020 is excluded as a transitional year.
- **β₃**: the DiD estimator — the differential post-shift change in outcomes for mothers vs. childless women. A significant positive β₃ (on employment) indicates a narrowing penalty.
- **X'**: controls (education, age group, marital status, religiosity, district — see `DEFAULT_CONTROLS` below); errors are clustered by individual (`IDPUF`).

The baseline employment regression is estimated on the full pooled sample and separately for Jewish and Arab women (`Leom == 1` / `Leom == 2`), to check whether the effect differs by population group.

Beyond the baseline, the project implements a fuller empirical strategy, tracked checkpoint-by-checkpoint in [`docs/ROADMAP.md`](docs/ROADMAP.md):
- an **intensive-margin** regression on usual weekly work hours (conditional on employment),
- a **gender placebo** test (fathers vs. childless men) to check the effect is motherhood-specific rather than a general parenthood/macro shift — an insignificant β₃ here supports the motherhood-specific reading,
- an occupation-level **WFH-exposure index** and a **triple-differences (DDD) mechanism regression** (`Employed ~ Mother×Post×WFH_Exposure`) testing whether the narrowing penalty is actually driven by an occupation's remote-work exposure, cross-referenced against literature anchors (Bloom; Cohen & Manor 2024),
- a robustness check comparing the full sample against `Muasak`-observed-only rows,
- and a set of descriptive/child-age breakdowns (employment trajectories by youngest child's age, on the premise that younger children demand more intensive care).

Two methodological gaps between the original research plan and the actual CBS extract were resolved as recorded decisions rather than left ambiguous — see [`docs/decisions/`](docs/decisions/):
- the WFH-exposure index anchors to **2021**, not the originally-planned 2020 (no 2020 raw extract exists for this project),
- the age control is the categorical **`GilNK`** age-group code, not continuous age/age² (no continuous age or birth-year variable exists in the raw extract).

## Data

- **Source**: Israeli CBS Labor Force Survey microdata. Raw files are yearly CSVs with Hebrew-transliterated variable names (e.g. `Muasak` = employed, `AvodaMeHaBayit` = works from home, `Leom` = population group).
- **Not included in this repo**: raw CSVs are gitignored and must be supplied locally. Edit `folder_path` at the top of `main.R` to point at your local data folder.
- **Sample**: women aged 25–59 by default, survey years 2017–2019 and 2021–2023 (2020 excluded — no raw extract exists for that year). `load_and_clean_data(folder_path, sex_filter = "men")` builds the analogous male subsample used by the gender placebo test.
- **Caching**: the first run cleans the raw CSVs and saves the result as `cleaned_df.rds` in the data folder; subsequent runs load that cache instead of re-cleaning. Delete/rename the `.rds` file to force a rebuild after changing `data_processing.R`.
- **Schema-drift guard**: before a fresh (non-cached) load, `check_schema_drift()` verifies that a handful of name-bounded column ranges — used by positional `select(-(a:b))` drops in `data_processing.R` — occupy the same columns across every year's CSV, so a future CBS format change fails loudly instead of silently dropping the wrong data.
- **Validation guard**: every load (cached or fresh) is checked by `validate_cleaned_df()`, which hard-fails (`stop()`) on impossible states (wrong sex code, out-of-range age group, a stray 2020 row, NAs in `Employed`/`Mother`/`Post`, zero rows) and warns on soft thresholds (a regression control with >5% NA, etc.).

## Setup & running

Dependencies: R with the `tidyverse` and `fixest` packages (no lockfile/renv — just install both). Do not add a new dependency without flagging it first (project convention).

```r
install.packages(c("tidyverse", "fixest"))
```

Then edit `folder_path` in `main.R` to your local data folder and run:

```r
source("main.R")
```

or from a shell: `Rscript main.R`.

This runs the full default pipeline — load/validate data, comparative stats, the three baseline regressions (pooled, Jewish, Arab), the intensive-margin regression, child-age descriptives, and diagnostics — then writes every result to `outputs/` (see below). Three pieces of the empirical strategy are implemented but **not wired into this default run** and must be invoked manually (each sources its own dependencies):

```r
# Robustness check: full sample vs. Muasak-observed-only
source("main.R"); basic_reg_comp(cleaned_df)

# Gender placebo test (loads and validates a separate male subsample)
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

Runs the `testthat` suite in `tests/testthat/` (data processing, validation, schema-drift, every regression function, export, and a full-pipeline smoke test) against fixture CSVs checked into the repo, exiting non-zero on any failure. Any change touching a function used elsewhere (`data_processing.R`, the controls list) should be green on this suite before being considered done.

## Project structure

| File | Function | Purpose |
|---|---|---|
| `main.R` | — | Entry point. Sources all modules, loads/validates/cleans data (with caching and schema-drift checking), runs comparative stats, the baseline regressions, the intensive-margin regression, child-age descriptives, and diagnostics, then exports every result to `outputs/`. |
| `data_processing.R` | `load_and_clean_data()` | Loads raw CSVs, filters to the analysis sample, and builds every derived variable (see below). Also defines `DEFAULT_CONTROLS`, the single source of truth for regression controls. |
| `validation.R` | `validate_cleaned_df()`, `check_schema_drift()` | Hard/soft-fail data-quality guards on the cleaned data, and a header-only guard against CBS column-order drift breaking the positional column drops. |
| `comparative_statistics.R` | `run_comparative_stats()` | Missingness audit, employment-variable audit (`Muasak` vs. `Employed` vs. work hours), employment rates by mother status, and a work-mobility-over-time trend plot. |
| `basic_regression.R` | `basic_reg()` | Primary DiD regression: `Employed ~ Mother + Post + Mother:Post + controls`, clustered by `IDPUF`. |
| `basic_reg_compared_data.R` | `basic_reg_comp()` | Robustness check comparing the full sample against `Muasak`-observed-only rows. Defined but **not called by default** from `main.R` — run manually if needed. |
| `intensive_margin_regression.R` | `run_intensive_margin_reg()` | Intensive-margin counterpart to `basic_reg()`: `WorkHoursCont ~ Mother + Post + Mother:Post + controls`, estimated on `Employed == 1` only. |
| `gender_placebo.R` | `run_gender_placebo()` | Loads/validates the male subsample and reruns `basic_reg()` on it (fathers vs. childless men), as a placebo for the motherhood-specific interpretation. Sourced by `main.R` but **not called by default**. |
| `wfh_exposure_index.R` | `build_wfh_exposure_index()` | Occupation-level (ISCO-08) WFH-exposure index, anchored to 2021 (see `docs/decisions/checkpoint6-wfh-anchor-year.md`). Not sourced by `main.R`; run manually. |
| `ddd_regression.R` | `run_ddd_regression()` | Triple-differences mechanism test: joins the exposure index onto the sample and estimates `Employed ~ Mother*Post*WFH_Exposure + controls`, plus a second-stage regression of per-occupation `Mother:Post` estimates on exposure. Depends on `wfh_exposure_index.R`; not sourced by `main.R`. |
| `employment_by_child_age.R` | `employment_by_child_age()` | Employment rates and a controlled regression by youngest-child age bin, with raw/adjusted-rate plots. |
| `Diagnostics.R` | `run_diagnostics()` | 2×2 DiD table, event-study pre-trend plot, and missing-value audits for the regression variables. |
| `export_results.R` | `export_all_results()` | Walks the heterogeneous result lists returned by every analysis function and writes each data frame to CSV and each `ggplot` to PNG under `outputs/`. |
| `run_tests.R` | — | `testthat` runner (`Rscript run_tests.R`); exits non-zero on failure. |

## Key variables

| Variable | Definition |
|---|---|
| `Employed` | `1` if `Muasak == 1` ("employed"), else `0` — unemployed and not-in-labor-force are both treated as not working. |
| `Mother` | `1` if the respondent has any children under 17 (sex-agnostic in derivation — read as "Father" for the male subsample used in the gender placebo test). |
| `Post` | `1` for survey years ≥ 2021 (the post-WFH-shift period). |
| `WFH` | Works-from-home indicator; only defined for 2021+ (not asked pre-COVID). Feeds the WFH-exposure index. |
| `WorkHoursCont` | Continuous usual weekly work hours, derived from the binned `ShaotAvodaBederechKlalNK` (bin medians; irregular-hours codes imputed from observed medians in the matching range). Dependent variable of the intensive-margin regression. |
| `TeudaGvoha` | Highest education, collapsed into 6 groups: Below High School, High School (no matriculation), Matriculation (Bagrut), Post-secondary non-academic, Academic Degree (BA/MA/PhD), Other/No Certificate. |
| `BirthContinent` | Country of birth grouped by continent (Israel kept as its own category rather than folded into Asia); a small multi-continent CBS code is bucketed as "Other". |
| `WorksOutsideLocality` | `1` if she commutes outside her locality of residence for work, derived from `DargatNayadut`; used in comparative statistics only, not as a regression control. |
| `MishlachYad_ISCO_08_2` | 2-digit ISCO-08 occupation code; the join key for the WFH-exposure index and DDD regression. |

`DEFAULT_CONTROLS` (defined once in `data_processing.R`, reused by `basic_regression.R`, `basic_reg_compared_data.R`, `intensive_margin_regression.R`, `employment_by_child_age.R`, `Diagnostics.R`, and `ddd_regression.R`): `MatzavMishpachti` (marital status), `Dat` (religiosity), `GilNK` (age group), `MachozMegurim` (district of residence), `TeudaGvoha` (education) — all treated as categorical factors.

## Outputs

`Rscript main.R` writes one file per result table/plot to `outputs/` (CSV for tables, PNG for plots) via `export_all_results()`. `outputs/` is **gitignored by default** — several breakdowns (e.g. the Arab-women-only stratified regression) can produce small cells from real CBS microdata, so nothing derived from it should be committed without a human explicitly reviewing it first for disclosure risk.

## Known limitations

- CBS survey weight columns (`MishkalSofi`, `MishkalShnati`, etc.) exist in the raw data but are not applied anywhere — all reported rates and regression coefficients are unweighted convenience-sample statistics, not population-representative estimates.
- The WFH-exposure index and age controls both deviate from the research doc's literal specification, as documented decisions (see `docs/decisions/`), because the raw CBS extract lacks a 2020 file and any continuous age/birth-year variable.

## Documentation map

Before implementing anything, read (in this order): [`docs/ROADMAP.md`](docs/ROADMAP.md) (the checkpoint in question), [`docs/LLD.md`](docs/LLD.md) (schema/contracts), [`docs/HLD.md`](docs/HLD.md) (why the gap exists), [`TESTING_BLUEPRINT.md`](TESTING_BLUEPRINT.md) (how to test it). The original research plan (research question, literature review, and initial empirical design) has been folded into the "Background" and "Research design" sections above; `docs/LLD.md`/`docs/HLD.md` reconcile it against the real codebase and are the authoritative reference for any gap between plan and implementation.

## License

See [`LICENSE`](LICENSE).
