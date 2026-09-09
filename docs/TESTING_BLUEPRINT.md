# Testing Blueprint

This document is a blueprint for adding a test suite to this project. No tests exist yet. It's grounded in the current state of the 7 R files in this repo (`main.R`, `data_processing.R`, `comparative_statistics.R`, `basic_regression.R`, `basic_reg_compared_data.R`, `employment_by_child_age.R`, `Diagnostics.R`) rather than generic R testing advice.

## Why this matters here specifically

Three real statistical bugs were found and fixed in this codebase's recent history: an asymmetric employment imputation, categorical variables silently entered into regressions as if they were numeric/linear, and a margins calculation that averaged categorical codes. None of these threw an error — they produced plausible-looking, quietly wrong numbers. That's exactly the failure mode a small, targeted test suite catches immediately and a human skim of console output does not.

## 1. Framework recommendation

**Use [`testthat`](https://testthat.r-lib.org/) (3rd edition).** It's the standard R testing framework, maintained by Posit (the `tidyverse` maintainer), and already idiomatic given this project's existing `tidyverse` + `fixest` dependencies.

This project is a set of scripts, not an R package (no `DESCRIPTION`/`NAMESPACE`/`R/` layout). Two ways to use `testthat` here:

- **Recommended now — lightweight, no restructuring**: create a `tests/testthat/` directory. Each test file starts by `source()`-ing the one `.R` file it targets (e.g. `source("../../data_processing.R")`), then contains ordinary `test_that()` blocks. Run everything with `testthat::test_dir("tests/testthat")`, or wrap that one line in a `run_tests.R` script at the repo root for a one-command entry point (mirroring how `main.R` is already the one-command entry point for the analysis itself).
- **Optional future step — package-ify**: add a minimal `DESCRIPTION` and move the six function-bearing files into `R/`. This unlocks `devtools::test()`, `devtools::check()`, and CI templates like `usethis::use_github_action("test-coverage")` essentially for free. Not a prerequisite for adopting `testthat` — worth doing only if the project keeps growing.

**Supporting tools:**

| Package | Purpose | Status |
|---|---|---|
| `testthat` | Test runner, assertions (`expect_equal`, `expect_true`, `expect_s3_class`, ...) | Required |
| `withr` | `withr::local_pdf()` (or base `pdf(nullfile())`) to redirect `Diagnostics.R`'s `dev.new()`/`iplot()` calls to a null graphics device during tests | Required — `Diagnostics.R` was directly observed this session falling back to `pdf(file="Rplots1.pdf")` when run headlessly; without this, tests either pop a window or litter the repo with stray PDFs |
| `vdiffr` | Pixel-level plot snapshot testing | Optional — adds a heavier dependency; the project's only stated dependencies today are `tidyverse` + `fixest`, so treat this as a stretch goal, not a baseline requirement |

No mocking package (`mockery`, `mockr`, etc.) is needed — see §4.

## 2. Target areas, prioritized

### Priority 1 — Critical (a silent error here corrupts every downstream number)

**`data_processing.R :: load_and_clean_data()`** — every recoding rule inside it:

| Derived variable | Logic to test |
|---|---|
| `Employed` | `1` iff `Muasak == 1`; `0` for `Muasak == 2` *and* for `Muasak == NA` (not-in-labor-force) |
| `WorkHoursCont` | Bins 0–10 map to fixed medians (`0,4,11,18,25.5,32,37,42,47,54.5,78.5`); code 11 → median of bins 1–5; code 12 → median of bins 6–10; code 99 → `NA` |
| `TeudaGvoha` | Codes `{0,1}→"Below High School"`, `2→"High School (no matriculation)"`, `3→"Matriculation (Bagrut)"`, `4→"Post-secondary, non-academic"`, `{5,6,7}→"Academic Degree (BA/MA/PhD)"`, `{8,9}→"Other/No Certificate"`, `99→NA` |
| `BirthContinent` | `10→"Israel"`, `{1,6,11,14}→"Asia"`, `{2,8,12,15}→"Africa"`, `{3,4,5,13}→"Europe"`, `9→"North America"`, `7→"Other"`, `16→NA` |
| `WorksOutsideLocality` | `DargatNayadut==1→0`, `DargatNayadut∈{2..7}→1`, `DargatNayadut∈{0,8}` or `NA→NA` |
| Filter block | `Min==2`, `GilNK` between 3 and 7 inclusive, `ShnatSeker ∈ {2017,2018,2019,2021,2022,2023}` (2020 excluded) |
| Factor conversion | `MatzavMishpachti`, `Dat`, `GilNK`, `MachozMegurim`, `MisparHorimYechidim` end up as `factor`, not numeric |

**The positional range-based column drops** — `select(-(a:b))` appears 7 times in `load_and_clean_data()` (e.g. `-(RamatDat:BituachLeumi)`). These depend on the raw CSV's *column order*, not column names. If CBS ever reorders or inserts a column in a future data release, one of these ranges could silently start dropping (or keeping) the wrong columns — no error, no warning, just wrong data downstream. This needs an explicit **schema-presence test** (assert a fixed list of expected-to-survive columns, e.g. `DargatNayadut`, `MachozYishuvAvoda`, `Leom`, `SemelEretzLeda`, are present in the output; assert a sample of expected-to-be-dropped columns, e.g. `RamatDat`, `BituachLeumi`, are absent), independent of and in addition to value-level tests.

### Priority 2 — High (core inferential outputs)

- **`basic_regression.R :: basic_reg()`** and the `controls` vector / formula-string construction. This exact list (`MatzavMishpachti`, `Dat`, `GilNK`, `MachozMegurim`, `TeudaGvoha`) is copy-pasted identically into `basic_regression.R`, `basic_reg_compared_data.R`, and `employment_by_child_age.R` — a **cross-file consistency test** belongs here specifically because of that duplication (see §3).
- **`employment_by_child_age.R`**'s recycled-predictions margins block: loops `map_dfr()` over `ChildAgeBin` levels, re-levels a temporary copy of the data, calls `predict()`, and averages. Complex enough logic (introduced this session, replacing an earlier buggy margins-at-means approach) that a regression here would be easy to introduce and easy to miss visually in a bar chart.
- **`Diagnostics.R`**'s event-study releveling: `factor(ShnatSeker, levels = c(2019, 2017, 2018, 2021, 2022, 2023))` then `i(ShnatSeker, Mother, ref = 2019)`. Relevel-order mistakes are a classic silent failure mode in event-study specifications — get the reference year wrong and every coefficient shifts meaning without any error being thrown.

### Priority 3 — Medium

- **`comparative_statistics.R :: run_comparative_stats()`** — missingness percentages, `Muasak`/`Employed` breakdowns, mother-vs-non-mother employment rates, mobility-by-year. Simpler `dplyr` pipelines than Priority 1/2, but still worth regression-guarding since these numbers likely go straight into a paper or presentation.
- **`basic_reg_compared_data.R :: basic_reg_comp()`** — same controls/formula pattern as `basic_reg()`. Lower priority only because it isn't called by default from `main.R`.

### Priority 4 — Integration/smoke only

- **`main.R`** is not a function — it's a top-level script (`rm(list=ls())`, a hardcoded `folder_path`, `source()` calls, `saveRDS`/`readRDS` caching, sequential calls into the other six files). It isn't a unit-test target as written; see §3 for how to cover it anyway, and §4 for the testability gap this creates.

## 3. Testing methodology

### Unit tests

Small, in-memory data, fully deterministic, no file I/O:

- **Table-driven recode tests** (highest value, lowest effort): one `test_that()` per derived variable in the Priority 1 table above, iterating every known input code and asserting the expected output. This is the single most direct guard against the exact class of bug (copy-paste/off-by-one in a code→category mapping) already found twice in this codebase's history.
- **`Employed` recode**: table-driven over `Muasak ∈ {1, 2, NA}`.
- **`run_comparative_stats()`**: 4–6 row hand-built fixtures where the missingness % and group means can be verified by hand-calculation, asserted with `expect_equal(..., tolerance = ...)`.
- **`controls` vector cross-file consistency**: read the `controls <- c(...)` definitions out of `basic_regression.R`, `basic_reg_compared_data.R`, and `employment_by_child_age.R` (or, more robustly, refactor them into one shared constant sourced by all three — flagged as an optional companion refactor, not required to write the test) and assert all three are identical. Cheap to write, catches drift directly and immediately — this is the same duplication that was manually kept in sync three separate times earlier this session.
- **Regression "contract" tests** for `basic_reg()` / `basic_reg_comp()` / `employment_by_child_age()`'s regression step: assert on *structure* — the returned list's shape, that the model is a `fixest` object (`expect_s3_class(model, "fixest")`), and that the expected coefficient names are present (e.g. `"Mother"`, `"Post"`, `"Mother:Post"`, and one dummy per factor level actually in the data) — plus, separately, one or two small **synthetic datasets with a hand-computable true DiD effect** (e.g., a crafted 2×2 group-by-period design with a known, exact treatment effect baked in) to check the regression math itself, rather than comparing against real output values that can't be reproduced in a test environment.

### Integration tests

Multi-stage, involving fixture files:

- **`load_and_clean_data()` end-to-end**, run against small synthetic CSV fixtures (~10–20 rows) placed in `tests/testthat/fixtures/`, covering every edge-case code in one pass: `Muasak ∈ {1, 2, NA}`; `ShaotAvodaBederechKlalNK ∈ {0, 1–10, 11, 12, 99}`; `TeudaGvoha ∈ {0–9, 99}`; `SemelEretzLeda` covering Israel, one code from each continent bucket, plus the two edge cases (code 7, code 16); `DargatNayadut ∈ {0, 1, 2–7, 8}`; `Leom ∈ {1, 2, 3}`. Assert: correct row filtering (women, age range, year set), presence of `Leom`/`SemelEretzLeda` in the output (previously dropped, now kept — a real regression risk if that change were ever accidentally reverted), absence of a sample of the ~90 explicitly-dropped columns, and that `DargatNayadut`/`MachozYishuvAvoda` survive the positional range drops.
- **A full-pipeline smoke test** mirroring `main.R`'s actual sequence — source every module, call `load_and_clean_data()` on the fixtures, then call `run_comparative_stats()`, `basic_reg()`, `employment_by_child_age()`, `run_diagnostics()` in order — asserting the whole chain runs without error or unexpected warning and every function returns the object shape it's documented to return. This is the practical stand-in for testing `main.R` itself (see §4).

### Mocking strategy

- **No mocking framework is needed for `load_and_clean_data()`.** It already takes `folder_path` as a parameter — pointing it at `tests/testthat/fixtures/` *is* the dependency injection; there's nothing to mock.
- **`main.R` is not parameterized** — hardcoded `folder_path`, direct `rm(list=ls())`, direct `saveRDS`/`readRDS`. This is a genuine testability gap, not something to mock around. See §4 for the recommended fix.
- **Graphics/interactive calls** (`dev.new()`, `iplot()`, `print(<ggplot>)`): don't mock the calls — redirect the graphics device to null (`withr::local_pdf()` or `pdf(nullfile())`) for the duration of the test, and assert on the *returned* `ggplot` object's underlying data via `ggplot_build(p)$data` rather than on rendered pixels.
- **`fixest::feols()`**: no mocking — it's fast and fully deterministic given fixed input data, so just use small in-memory data frames directly.

## 4. Testability gap worth flagging: `main.R`

`main.R` can't be unit-tested as written because it isn't a function — it's a script with a hardcoded path and global-environment side effects. Two options, in order of recommendation:

1. **Cover it via the full-pipeline smoke test described in §3** (source the modules, call each function directly against fixtures, in the same order `main.R` uses). No changes to `main.R` required. This is sufficient for the near term.
2. **Optional refactor**: extract `main.R`'s body into a `run_pipeline(folder_path, rds_file_path, use_cache = TRUE)` function that `main.R` itself then just calls with the real hardcoded path. This would let the *actual* orchestration logic (not just a reimplementation of its sequence in a test) be exercised in-process against fixtures. Worth doing if the pipeline keeps growing, not required to have a working test suite today.

## 5. Suggested directory layout

```
tests/
  testthat/
    fixtures/
      sample_2019_Data.csv       # synthetic, ~10-20 rows, covers all edge-case codes
      sample_2021_Data.csv       # a second year, so Post/year-filtering logic is exercised
    test-data_processing.R       # Priority 1
    test-basic_regression.R      # Priority 2
    test-employment_by_child_age.R
    test-diagnostics.R
    test-comparative_statistics.R
    test-pipeline_smoke.R        # Priority 4 / §3 integration
run_tests.R                      # one-line entry point: testthat::test_dir("tests/testthat")
```

## 6. Suggested rollout order

1. Priority 1 table-driven recode tests (highest value, no fixtures needed beyond tiny vectors) — start here.
2. Fixture CSVs + `load_and_clean_data()` integration tests, including the schema-presence check on the positional range drops.
3. `controls` cross-file consistency test.
4. Priority 2 regression contract + hand-computable-DiD tests.
5. Full-pipeline smoke test.
6. Priority 3 (`comparative_statistics.R`, `basic_reg_comp()`).
7. Optional: `main.R` → `run_pipeline()` refactor, `vdiffr` snapshots, package-ify + CI.
