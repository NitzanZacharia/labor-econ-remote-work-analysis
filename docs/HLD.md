# High-Level Design: Motherhood Penalty / WFH Analysis Pipeline

## 1. Purpose & Scope

This document describes the system that implements the research design in [`motherhood_penalty_wfh_research.md`](../motherhood_penalty_wfh_research.md) (Parts 1–4): an individual-level Difference-in-Differences analysis of whether the post-COVID shift to remote work altered the "motherhood penalty" in the Israeli labor market.

It covers **both** the system as it runs today and the system the research doc specifies — the two are not the same. Every section below marks, explicitly, which parts are implemented and which are required but not yet built. Treat the "Required but not yet built" subsection of §4 as the roadmap from current state to full research-doc scope.

## 2. System Architecture

**Execution model**: a single-machine, local R session (RStudio or `Rscript`). There is no database, API, scheduler, or CI — `main.R` is the sole orchestrator, run manually. All state between runs is a single cached file (`cleaned_df.rds`); all output today is printed to the console or rendered as an interactive plot, not persisted to disk.

**Layers:**

| Layer | File(s) | Role |
|---|---|---|
| Raw Data Layer | *(external — not in repo)* | Yearly CBS Labor Force Survey CSVs + `H20231031Codebook.xlsx`, at a path hardcoded in `main.R` (`folder_path`). Gitignored (`*.csv`). |
| Ingestion & Cleaning Layer | `data_processing.R` | `load_and_clean_data(folder_path)` — reads, filters, recodes, and prunes raw data into an analysis-ready data frame. |
| Cached Processed-Data Layer | `cleaned_df.rds` | Disk-persisted output of the cleaning layer; `main.R` loads this if present instead of re-cleaning. |
| Descriptive/Comparative Statistics Layer | `comparative_statistics.R` | `run_comparative_stats()` — missingness, employment-variable audit, group means, mobility trend. |
| Modeling Layer | `basic_regression.R`, `basic_reg_compared_data.R`, `employment_by_child_age.R` | Fits the DiD regression(s) and heterogeneity breakdowns. |
| Diagnostics/Validation Layer | `Diagnostics.R` | Parallel-trends event study, 2×2 DiD table, missing-value audits. |
| Orchestration Layer | `main.R` | Sources every module and calls them in sequence; the only entry point. |
| Output Layer | *(none dedicated)* | `etable()` tables and `ggplot2` plots printed/rendered interactively. **Gap**: nothing writes a table or plot to disk — the research doc's "drafting findings" step (Part 1 §VI) will need one. |

**Layer diagram:**

```
 [ Raw CBS LFS CSVs, external ]
              |
              v
 [ Ingestion & Cleaning: data_processing.R ]
              |
              v
 [ Cached Processed Data: cleaned_df.rds ]
              |
   +----------+----------+--------------------+
   v          v          v                    v
[ Comparative Stats ] [ Modeling ] [ Child-Age Het. ] [ Diagnostics ]
   |          |          |                    |
   +----------+----------+--------------------+
              v
 [ Output: console tables + interactive plots ]  <-- no persisted export today
```

## 3. Data Flow

The lifecycle of the labor force data, from raw ingestion through to regression output:

1. **Ingestion** — `load_and_clean_data()` reads every yearly CSV in `folder_path` (`read_csv` + `map_df`, tagged with a `file_source` column).
2. **Sample filtering** — restricts to `Min == 2` (women only), `GilNK` between 3–7 (ages 25–59), and survey years `{2017,2018,2019,2021,2022,2023}` (2020 excluded as a transitional year, per the research doc).
   > **Gap**: the `Min == 2` filter happens at the very first filtering step, before any downstream logic. This is why the research doc's **Gender Placebo Test** (Part 2 §3 / Part 4 §5 — replicate the model for fathers vs. childless men) cannot run against today's `cleaned_df` at all; men are excluded before the data frame even exists. Closing this gap needs either a sample-selection parameter on `load_and_clean_data()` or a parallel pipeline.
3. **Variable construction** (implemented, all in `data_processing.R`):
   - `Employed` — extensive-margin outcome, `1` iff `Muasak == 1`.
   - `WorkHoursCont` — intensive-margin *variable*, built from binned work hours with median imputation for irregular-hours codes.
     > **Gap**: this variable exists and is summarized descriptively in `comparative_statistics.R`, but is **not yet wired as a regression dependent variable** anywhere. The research doc's core spec (Part 2 §1 / Part 4 §2) models *two* margins — employment and hours — as parallel DiD regressions; only the employment one is implemented.
   - `Mother`, `Post` — treatment and period dummies, matching the research doc's definitions exactly (children <17; post ≥ 2021).
   - `WFH` — raw work-from-home indicator (2021+ only).
   - `TeudaGvoha` (education, collapsed to 6 groups), `BirthContinent` (country of birth by continent), `WorksOutsideLocality` (commuting indicator) — advisor-feedback-driven engineered variables (Part 3 §3).
   - `MishlachYad_ISCO_08_2` — the raw ISCO occupation code is already parsed to numeric here, but not yet aggregated into anything.
     > **Gap**: the research doc's **WFH-Exposure Index / DDD mechanism test** (Part 2 §2, Part 4 §4) needs this occupation code turned into an occupation-level WFH-exposure measure (anchored to the 2020 WFH variable per the doc) and a second-stage `β_j ~ WFH_Exposure_j` regression. Neither exists yet — this is the single largest unbuilt piece of the research design.
   - Categorical controls (`MatzavMishpachti`, `Dat`, `GilNK`, `MachozMegurim`, `TeudaGvoha`) converted to factors.
     > **Note**: the research doc's Part 4 §2 lists continuous `Age`/`Age²` as controls, while the actually-implemented control is `GilNK`, a categorical age *group* (matching Part 3 §3's advisor feedback for categorical dummies instead). This is a discrepancy between two parts of the research doc itself, not something this HLD resolves unilaterally — flagged here for the researchers to reconcile.
4. **Column pruning** — ~90 irrelevant raw columns dropped via three mechanisms: an explicit name list, a regex prefix match, and several positional range drops (`select(-(a:b))`, order-dependent on the raw CSV schema).
5. **Caching** — result saved to `cleaned_df.rds`; subsequent runs load the cache instead of re-cleaning.
6. **Fan-out to analysis** (all implemented, from `main.R`):
   - `run_comparative_stats(cleaned_df)` — implements Part 3 §4 (descriptive means, dependent-variable baselines).
   - `basic_reg(cleaned_df)` — the core DiD regression (Part 2 §1 / Part 4 §3), pooled sample.
   - `basic_reg(filter(cleaned_df, Leom == 1))` / `== 2` — Jewish/Arab stratified regressions, implementing Part 3 §5's "Demographic Stratification" advisor feedback.
   - `employment_by_child_age(cleaned_df)` — implements Part 2 §3's "Child Age Sensitivity Analysis."
   - `run_diagnostics(cleaned_df)` — implements Part 2 §3 / Part 4 §5's Parallel Trends check (event-study plot) and a 2×2 DiD summary table.
7. **Terminal output** — `fixest::etable()` regression tables and `ggplot2` plots, printed/rendered to the interactive session. No file is written.

## 4. Needed Components

### 4.1 Existing

| File | Function | Implements (research doc §) | Key dependencies |
|---|---|---|---|
| `main.R` | — (orchestrator) | Part 1 §VI pipeline sequencing | — |
| `data_processing.R` | `load_and_clean_data()` | Part 3 §§1–3 (cleaning, DV definition, controls); Part 4 §§1–2 (data source, variable construction) | `tidyverse` |
| `comparative_statistics.R` | `run_comparative_stats()` | Part 3 §4 (descriptive statistics) | `tidyverse` |
| `basic_regression.R` | `basic_reg()` | Part 2 §1 / Part 4 §3 (core DiD, extensive margin only) | `fixest` |
| `basic_reg_compared_data.R` | `basic_reg_comp()` | Robustness check (full sample vs. `Muasak`-observed only); not called by default | `fixest` |
| `employment_by_child_age.R` | `employment_by_child_age()` | Part 2 §3 (Child Age Sensitivity) | `tidyverse`, `fixest` |
| `Diagnostics.R` | `run_diagnostics()` | Part 2 §3 / Part 4 §5 (Parallel Trends, 2×2 DiD) | `tidyverse`, `fixest` |

R dependencies in use today: **`tidyverse`**, **`fixest`**. No lockfile/renv; no database, API, or scheduling dependency.

### 4.2 Required but not yet built

| Component | Research-doc reference | Notes |
|---|---|---|
| Intensive-margin regression | Part 2 §1, Part 4 §2 | `WorkHoursCont ~ Mother + Post + Mother:Post + controls`, parallel to `basic_reg()`. `WorkHoursCont` already exists as a variable — this is a modeling gap, not a data gap. |
| Occupational WFH-Exposure Index | Part 2 §2, Part 4 §4 | Needs an occupation-level (`MishlachYad_ISCO_08_2`) aggregation of the 2020 WFH variable, cross-referenced against the literature anchors the doc names (Bloom; Cohen & Manor 2024). The raw occupation code is already parsed in `data_processing.R`; the index itself doesn't exist. |
| DDD mechanism regression | Part 2 §2, Part 4 §4 | Two pieces: (a) a triple-interaction `Mother × Post × WFH_Potential` term in the main model, and (b) the second-stage `β_j = γ_0 + γ_1·WFH_Exposure_j + ε_j` regression on per-occupation DiD estimates. Depends on the WFH-Exposure Index above. |
| Gender Placebo Test | Part 2 §3, Part 4 §5 | Requires re-including men, which `data_processing.R`'s `Min==2` filter currently forecloses entirely (see §3 above). Needs a sample-selection parameter or a parallel pipeline, plus a fathers-vs-childless-men variant of `basic_reg()`. |
| Continuous `Age`/`Age²` controls | Part 4 §2 | Not present; current controls use the categorical `GilNK` age group instead (see the discrepancy note in §3). |
| Persisted output/export layer | Part 1 §VI ("drafting findings") | No component writes regression tables or plots to disk today; everything is console/interactive-only. |

### 4.3 Reconciliation note

Part 3 §1 of the research doc ("Variables to Exclude") says to drop the work-mobility variable **entirely**. What's actually implemented (this session, per a later round of advisor feedback) is different: `WorksOutsideLocality` is built and reported in `run_comparative_stats()`, but deliberately excluded from every regression's `controls` list. This HLD records that as a later refinement of the written doc, not a contradiction — the researchers should confirm `motherhood_penalty_wfh_research.md` gets updated to match if this is the intended final behavior.
