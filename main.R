# main.R

# ── 1. Clear environment and load modules ─────────────────────────────────────
rm(list = ls())
source("data_processing.R")
source("comparative_statistics.R")
source("basic_regression.R")
source("basic_reg_compared_data.R")
source("Diagnostics.R")
source("employment_by_child_age.R")
source("validation.R")
source("intensive_margin_regression.R")
source("intensive_margin_lee_bounds.R")
source("gender_placebo.R")
source("export_results.R")

# Load modules required for the WFH exposure index and DDD mechanism test
source("wfh_exposure_index.R")
source("wfh_exposure_cells.R")
source("isco_masking_diagnostics.R")
source("ddd_collinearity_diagnostics.R")
source("ddd_regression.R")

# ── 2. Configure paths ────────────────────────────────────────────────────────
message("Edit folder paths if needed!")
folder_path   <- "G:/My Drive/Uni/econ/csv_data"
rds_file_path <- paste0(folder_path, "/cleaned_df.rds")

# ── 3. Execute data pipeline (with caching) ───────────────────────────────────
# Cache validity is tied to data_processing.R's content, not just to the RDS file's existence --
# otherwise a stale cache built before a data_processing.R change (e.g. a corrected WFH coding
# rule, or a new derived column) keeps getting silently reused with no error. The hash is stored
# in a small sidecar file next to the cache.
cache_meta_path       <- paste0(rds_file_path, ".meta.rds")
data_processing_hash  <- unname(tools::md5sum("data_processing.R"))

cache_is_valid <- file.exists(rds_file_path) && file.exists(cache_meta_path) &&
  identical(readRDS(cache_meta_path)$data_processing_hash, data_processing_hash)

if (cache_is_valid) {
  message("Found saved RDS file (data_processing.R unchanged) — loading pre-cleaned data...")
  cleaned_df <- readRDS(rds_file_path)
} else {
  if (file.exists(rds_file_path)) {
    message("data_processing.R has changed since the cache was built — invalidating cache...")
  }
  message("Checking raw CSV schema for column-order drift...")
  check_schema_drift(folder_path)
  message("Saved RDS not found or stale — loading and cleaning raw data...")
  cleaned_df <- load_and_clean_data(folder_path)
  message("Saving cleaned data for future use...")
  saveRDS(cleaned_df, file = rds_file_path)
  saveRDS(list(data_processing_hash = data_processing_hash), file = cache_meta_path)
}

message("Validating cleaned data...")
validate_cleaned_df(cleaned_df)

message("Checking IDPUF panel structure (cluster-SE unit vs. Mother/Post design)...")
idpuf_panel_check <- check_idpuf_panel_structure(cleaned_df)

message("Checking WFH_RefWeek's NA rationale against AvadBeshavua...")
wfh_refweek_check <- check_wfh_refweek_avadbeshavua(cleaned_df)

# ── 4. Comparative statistics ─────────────────────────────────────────────────
message("Running comparative statistics...")
comp_stats <- run_comparative_stats(cleaned_df)

# ── 5. Run regressions ────────────────────────────────────────────────────────
message("Running basic regression model...")
baseline_results <- basic_reg(cleaned_df)

message("Running basic regression model — Jewish women only...")
baseline_jewish <- basic_reg(filter(cleaned_df, Leom == 1))

message("Running basic regression model — Arab women only...")
baseline_arab <- basic_reg(filter(cleaned_df, Leom == 2))

message("Running intensive-margin (work hours) regression...")
intensive_results <- run_intensive_margin_reg(cleaned_df)

message("Running intensive-margin Lee (2009) trimming bounds (selection-on-employment correction)...")
intensive_lee_bounds <- run_intensive_margin_lee_bounds(cleaned_df)

# ── 6. Run descriptive stats ────────────────────────────────────────────────────────
message("Running employment_by_child_age...")
emp_res <- employment_by_child_age(cleaned_df)

# ── 7. Debug ─────────────────────────────────────────────────────────
# Diagnostics.R's event-study plot draws to whatever device is active rather than opening its own
# (see the comment there) -- wrap the call in an explicit device targeting outputs/ so a real run
# produces a saved plot instead of leaking an auto-numbered Rplots*.pdf into the repo root.
pdf(file.path("outputs", "event_study_pretrend.pdf"))
diagnostics_results <- run_diagnostics(cleaned_df)
dev.off()

# Results are exported once, at the very end of the script (── 9 ──), so that §8's WFH-exposure
# measures and DDD regressions are captured in the same outputs/ artifact set as everything above
# -- previously this export call ran here, before this section existed, so none of its results
# ever reached disk (Checkpoint 9/10 gap).

# ── 8. WFH-Exposure Measures & DDD Regression ─────────────────────────────────
# Four separate measures, four separate purposes. They are NOT combined into one "best" index fed
# to a single regression -- an earlier version of this section did that (swapping the theoretical
# index for realized-2022-23 values above an arbitrary gap threshold, with no account of sampling
# noise), which both contaminated the DDD's exposure regressor with post-treatment behavior and
# let a 4-observation occupation cell (ISCO 63) swing the ranking. See
# docs/decisions/calibrated-exposure-and-cell-ddd.md for the full argument.
message("Building the WFH-exposure measures...")

# (a) External, exogenous teleworkability (Dingel & Neiman via O*NET/SOC->ISCO crosswalk).
# Pre-period by construction, immune to Israel's own COVID-era WFH behavior -- but a US-task-based
# measure, so it misclassifies occupations where Israeli institutional practice diverges sharply
# (teaching is the clear case: D&N scores it near-ceiling teleworkable, but Israeli schools stayed
# in-person by Ministry of Education policy).
exposure_external <- build_exposure_isco2()

# (b) Statistically-calibrated version of (a): corrects occupations where the realized-vs-D&N gap
# is large AND well-powered enough that it can't be sampling noise (a cluster-robust one-sided
# test against the gap_threshold, not a flat sample-size floor -- see calibrate_isco_exposure()'s
# own documentation in wfh_exposure_cells.R for why). Still draws on 2022-23 realized data, which
# sits inside the post-period, so this is a documented compromise, not a fully pre-treatment
# measure -- report (c)/(d) alongside it so the paper shows whether conclusions depend on it.
exposure_calibrated <- calibrate_isco_exposure(cleaned_df, exposure_external)
message(sprintf(
  "  calibration swapped %d of %d occupations for realized Israeli values (gap > 0.5, statistically distinguishable from sampling noise at 95%% confidence):",
  sum(exposure_calibrated$swap), nrow(exposure_calibrated)
))
print(exposure_calibrated %>% filter(swap) %>%
        select(ISCO2, n, tele_ext, realized_wfh, gap, se_clustered, margin) %>%
        as.data.frame(), digits = 3)

# Sensitivity check: exposure_calibrated (and exposure_realized/exposure_cells below) is built by
# dropping every disclosure-masked-ISCO row via !is.na(ISCO2) -- masking concentrates in thin
# occupation cells, so this checks whether masked rows' realized WFH looks different from unmasked
# rows' within the same coarse (ISCO1) occupation family, as a proxy for whether that dropped
# subsample is likely to be biasing the exposure index. See isco_masking_diagnostics.R.
message("Checking ISCO disclosure-masking sensitivity (masked vs. unmasked realized WFH)...")
isco_masking_check <- check_isco_masking_sensitivity(cleaned_df)

# (c) Realized Israeli WFH by occupation, anchored per
# docs/decisions/checkpoint6-wfh-anchor-year.md. Post-treatment by construction -- a robustness
# check, not a substitute for (a)/(b). min_n = 200 drops occupations too thin to trust (without a
# floor, a 4-observation cell can dominate the ranking -- see ISCO 63 above).
exposure_realized <- build_wfh_exposure_index(cleaned_df, ref_year = 2021, min_n = 200)

# (d) Pre-period (2017-2019) shift-share exposure by demographic cell (sex x age x education x
# district), built from the calibrated occupation-level score (b). Unlike (a)-(c), this is defined
# for every row of cleaned_df -- employed and non-employed alike -- so it's the only one of the
# four that doesn't condition the third difference on Employed, the regression's own outcome. This
# is the primary exposure measure for the causal DDD.
exposure_cells <- build_exposure_cells(
  cleaned_df,
  exposure_calibrated %>% select(ISCO2, tele_ext = wfh_exposure_calibrated)
)

# ── 8a. Primary DDD: cell-based exposure, defined for the full sample ─────────
# Two specs, reported side by side. WFH_Exposure is built from (GilNK, TeudaGvoha, MachozMegurim)
# -- the same three variables DEFAULT_CONTROLS already includes additively -- so Spec 1's
# WFH_Exposure carries substantial overlap with its own controls (at the time of writing: 74.5% of
# its variance explained by GilNK+TeudaGvoha+MachozMegurim alone; design-matrix condition number
# 267.8 -- see check_spec1_collinearity() below, which recomputes both from the live data on every
# run rather than leaving them as a static claim that could go stale as the microdata changes).
# Spec 2 is the standard fix for a shift-share regressor like this: fully interacted cell fixed
# effects absorb WFH_Exposure's own cross-cell level entirely (its bare main effect becomes exactly
# collinear with the FE and fixest drops it automatically), so identification comes only from
# Mother/Post's within-cell variation against the (cell-constant) exposure value -- the
# Mother:WFH_Exposure / Post:WFH_Exposure / Mother:Post:WFH_Exposure interactions remain identified
# either way, since Mother and Post vary within a cell even though WFH_Exposure itself doesn't.
message("Running primary DDD (cell-based exposure, calibrated, full sample)...")
ddd_df <- cleaned_df %>%
  left_join(exposure_cells, by = c("Min", "GilNK", "TeudaGvoha", "MachozMegurim"))

cell_fe_vars    <- c("GilNK", "TeudaGvoha", "MachozMegurim")  # matches build_exposure_cells()'s
                                                               # cell_vars, minus the constant Min
other_controls  <- setdiff(DEFAULT_CONTROLS, cell_fe_vars)

ddd_primary_additive <- feols(
  as.formula(paste("Employed ~ Mother * Post * WFH_Exposure +",
                    paste(DEFAULT_CONTROLS, collapse = " + "))),
  data = ddd_df, cluster = ~IDPUF
)
ddd_primary_fe <- feols(
  as.formula(paste("Employed ~ Mother * Post * WFH_Exposure +",
                    paste(other_controls, collapse = " + "),
                    "|", paste(cell_fe_vars, collapse = "^"))),
  data = ddd_df, cluster = ~IDPUF
)
primary_ddd_table <- etable(
  ddd_primary_additive, ddd_primary_fe,
  headers = c("Spec 1: additive controls", "Spec 2: interacted cell FE"), digits = 4
)
print(primary_ddd_table)

message("Checking Spec 1's collinearity at runtime (see comment above)...")
spec1_collinearity_check <- check_spec1_collinearity(ddd_df, cell_fe_vars, DEFAULT_CONTROLS)

# ── 8b-8d. Robustness: occupation-level DDD + mechanism regression ────────────
message("Running robustness DDD (calibrated occupation-level index)...")
ddd_calibrated <- run_ddd_regression(
  cleaned_df,
  exposure_calibrated %>% select(occupation_code = ISCO2, wfh_exposure = wfh_exposure_calibrated)
)

message("Running robustness DDD (raw external Dingel & Neiman index)...")
ddd_external <- run_ddd_regression(
  cleaned_df,
  exposure_external %>% select(occupation_code = ISCO2, wfh_exposure = tele_ext)
)

message("Running robustness DDD (realized Israeli index, 2021 anchor)...")
ddd_realized <- run_ddd_regression(cleaned_df, exposure_realized)

# ── 9. Export results ─────────────────────────────────────────────────────────
# idpuf_panel_check is deliberately NOT included here: its idpuf_years/idpuf_periods tables are
# keyed by individual IDPUF, which is closer to raw identifiable microdata than the aggregate
# tables everything else in this list produces -- per this project's disclosure-risk convention
# (CLAUDE.md, Checkpoint 9), only its console-printed summary counts are surfaced, not a
# persisted per-person roster.
message("Exporting results to outputs/...")
export_all_results(list(
  comparative_stats = comp_stats,
  basic_reg = baseline_results,
  basic_reg_jewish = baseline_jewish,
  basic_reg_arab = baseline_arab,
  intensive_margin = intensive_results,
  intensive_margin_lee_bounds = intensive_lee_bounds,
  employment_by_child_age = emp_res,
  diagnostics = diagnostics_results,
  isco_masking_sensitivity = isco_masking_check,
  wfh_exposure_external = exposure_external,
  wfh_exposure_calibrated = exposure_calibrated,
  wfh_exposure_realized = exposure_realized,
  wfh_exposure_cells = exposure_cells,
  ddd_primary = primary_ddd_table,
  ddd_calibrated = ddd_calibrated,
  ddd_external = ddd_external,
  ddd_realized = ddd_realized
))
