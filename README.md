# labor-econ-remote-work-analysis

Empirical analysis on the impact of Remote Work on the Motherhood Penalty, using Israeli Central Bureau of Statistics (CBS) Labor Force Survey microdata.

## Research design

The core analysis is a mother/non-mother × pre/post-2021 difference-in-differences design, using the COVID-era shift toward remote work as the "post" treatment period. The baseline employment regression is estimated:
- on the full pooled sample,
- and separately for Jewish and Arab women (`Leom == 1` / `Leom == 2`), to check whether the effect differs by population group.

A robustness-check variant and a set of descriptive/child-age breakdowns are also included (see below).

## Data

- **Source**: Israeli CBS Labor Force Survey microdata. Raw files are yearly CSVs with Hebrew-transliterated variable names (e.g. `Muasak` = employed, `AvodaMeHaBayit` = works from home, `Leom` = population group).
- **Not included in this repo**: raw CSVs are gitignored and must be supplied locally. Edit `folder_path` at the top of `main.R` to point at your local data folder (it also expects `H20231031Codebook.xlsx` or an equivalent CBS codebook there for reference).
- **Sample**: women aged 25–59, survey years 2017–2019 and 2021–2023 (2020 excluded).
- **Caching**: the first run cleans the raw CSVs and saves the result as `cleaned_df.rds` in the data folder; subsequent runs load that cache instead of re-cleaning. Delete/rename the `.rds` file to force a rebuild after changing `data_processing.R`.

## Setup & running

Dependencies: R with the `tidyverse` and `fixest` packages (no lockfile/renv — just install both).

```r
install.packages(c("tidyverse", "fixest"))
```

Then edit `folder_path` in `main.R` to your local data folder and run:

```r
source("main.R")
```

or from a shell: `Rscript main.R`.

## Project structure

| File | Function | Purpose |
|---|---|---|
| `main.R` | — | Entry point. Sources all modules, loads/cleans data (with caching), then runs comparative stats, the three regressions, child-age descriptives, and diagnostics in sequence. |
| `data_processing.R` | `load_and_clean_data()` | Loads raw CSVs, filters to the analysis sample, and builds every derived variable (see below). |
| `comparative_statistics.R` | `run_comparative_stats()` | Missingness audit, employment-variable audit (`Muasak` vs. `Employed` vs. work hours), employment rates by mother status, and a work-mobility-over-time trend plot. |
| `basic_regression.R` | `basic_reg()` | Primary DiD regression: `Employed ~ Mother + Post + Mother:Post + controls`, clustered by `IDPUF`. |
| `basic_reg_compared_data.R` | `basic_reg_comp()` | Robustness check comparing the full sample against `Muasak`-observed-only rows. Defined but **not called by default** from `main.R` — run manually if needed. |
| `employment_by_child_age.R` | `employment_by_child_age()` | Employment rates and a controlled regression by youngest-child age bin, with adjusted-rate plots. |
| `Diagnostics.R` | `run_diagnostics()` | 2×2 DiD table, event-study pre-trend plot, and missing-value audits for the regression variables. |

## Key variables

| Variable | Definition |
|---|---|
| `Employed` | `1` if `Muasak == 1` ("employed"), else `0` — unemployed and not-in-labor-force are both treated as not working. |
| `Mother` | `1` if the respondent has any children under 17. |
| `Post` | `1` for survey years ≥ 2021 (the post-WFH-shift period). |
| `WFH` | Works-from-home indicator; only defined for 2021+ (not asked pre-COVID). |
| `WorkHoursCont` | Continuous usual weekly work hours, derived from the binned `ShaotAvodaBederechKlalNK` (bin medians; irregular-hours codes imputed from observed medians in the matching range). |
| `TeudaGvoha` | Highest education, collapsed into 6 groups: Below High School, High School (no matriculation), Matriculation (Bagrut), Post-secondary non-academic, Academic Degree (BA/MA/PhD), Other/No Certificate. |
| `BirthContinent` | Country of birth grouped by continent (Israel kept as its own category rather than folded into Asia); a small multi-continent CBS code is bucketed as "Other". |
| `WorksOutsideLocality` | `1` if she commutes outside her locality of residence for work, derived from `DargatNayadut`; used in comparative statistics only, not as a regression control. |

Regression controls (`basic_regression.R`, `basic_reg_compared_data.R`, `employment_by_child_age.R`, `Diagnostics.R`): `MatzavMishpachti` (marital status), `Dat` (religiosity), `GilNK` (age group), `MachozMegurim` (district of residence), `TeudaGvoha` (education) — all treated as categorical factors.

## Known limitations

- `main.R` sources `"diagnostics.R"` (lowercase) while the file on disk is `Diagnostics.R`. This works on case-insensitive filesystems (Windows/Mac) but will break on case-sensitive ones (Linux/CI).
- CBS survey weight columns (`MishkalSofi`, `MishkalShnati`, etc.) exist in the raw data but are not applied anywhere — all reported rates and regression coefficients are unweighted convenience-sample statistics, not population-representative estimates.
- No automated test suite; verification is manual via console/plot output.

## License

See [`LICENSE`](LICENSE).
