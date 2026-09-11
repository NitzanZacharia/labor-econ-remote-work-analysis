# main.R

# ── 1. Clear environment and load modules ─────────────────────────────────────
rm(list = ls())
source(file.path("scripts", "data_processing.R"))
source(file.path("scripts", "comparative_statistics.R"))
source(file.path("scripts", "basic_regression.R"))
source(file.path("scripts", "basic_reg_compared_data.R"))
source(file.path("scripts", "Diagnostics.R"))
source(file.path("scripts", "employment_by_child_age.R"))
source(file.path("scripts", "validation.R"))
source(file.path("scripts", "intensive_margin_regression.R"))
source(file.path("scripts", "intensive_margin_lee_bounds.R"))
source(file.path("scripts", "gender_placebo.R"))
source(file.path("scripts", "export_results.R"))

# Load modules required for the WFH exposure index and DDD mechanism test
source(file.path("scripts", "wfh_exposure_index.R"))
source(file.path("scripts", "wfh_exposure_cells.R"))
source(file.path("scripts", "isco_masking_diagnostics.R"))
source(file.path("scripts", "ddd_collinearity_diagnostics.R"))
source(file.path("scripts", "ddd_regression.R"))
source(file.path("scripts", "wfh_first_stage_check.R"))
source(file.path("scripts", "ddd_mde_diagnostics.R"))

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
data_processing_hash  <- unname(tools::md5sum(file.path("scripts", "data_processing.R")))

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

# calibrate_isco_exposure()/build_wfh_exposure_index()/build_exposure_cells() below must NOT be
# built from cleaned_df alone: cleaned_df is the exact women-25-59 analysis sample that later
# populates the primary DDD as Mother/Post/Employed, and wfh_exposure_index.R's own header comment
# already warns against exactly this ("passing the analysis sample builds the third difference out
# of the same people who enter the regression -- prefer a frame that excludes them, or at minimum
# covers all workers"). build_exposure_cells() already stratifies by Min (sex) as a cell variable
# (its first parameter is even named raw_all), so adding men doesn't change its women-cell output
# at all -- but calibrate_isco_exposure()/build_wfh_exposure_index() aggregate by occupation only,
# with no sex conditioning, so adding men's realized WFH behavior to the pool genuinely breaks the
# mechanical link between "this occupation's exposure score" and "the exact population the DDD
# studies."
message("Loading men's data (sex_filter = 'men') so exposure construction isn't built from the ",
        "exact women-25-59 analysis sample (see wfh_exposure_index.R's header comment)...")
rds_file_path_men   <- paste0(folder_path, "/cleaned_df_men.rds")
cache_meta_path_men <- paste0(rds_file_path_men, ".meta.rds")
cache_is_valid_men <- file.exists(rds_file_path_men) && file.exists(cache_meta_path_men) &&
  identical(readRDS(cache_meta_path_men)$data_processing_hash, data_processing_hash)
if (cache_is_valid_men) {
  message("Found saved RDS file for men (data_processing.R unchanged) — loading pre-cleaned data...")
  cleaned_men_for_exposure <- readRDS(rds_file_path_men)
} else {
  cleaned_men_for_exposure <- load_and_clean_data(folder_path, sex_filter = "men")
  saveRDS(cleaned_men_for_exposure, file = rds_file_path_men)
  saveRDS(list(data_processing_hash = data_processing_hash), file = cache_meta_path_men)
}
exposure_population_df <- bind_rows(cleaned_df, cleaned_men_for_exposure)

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
exposure_calibrated <- calibrate_isco_exposure(exposure_population_df, exposure_external)
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
exposure_realized <- build_wfh_exposure_index(exposure_population_df, ref_year = 2021, min_n = 200)

# (d) Pre-period (2017-2019) shift-share exposure by demographic cell (sex x age x education x
# district), built from the calibrated occupation-level score (b). Unlike (a)-(c), this is defined
# for every row of cleaned_df -- employed and non-employed alike -- so it's the only one of the
# four that doesn't condition the third difference on Employed, the regression's own outcome. This
# is the primary exposure measure for the causal DDD.
exposure_cells <- build_exposure_cells(
  exposure_population_df,
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

# WFH_Exposure is constant within a (GilNK, TeudaGvoha, MachozMegurim) cell (<=210 distinct cells),
# not at the individual level -- clustering at IDPUF here understates the true SE on
# WFH_Exposure/Mother:WFH_Exposure/Post:WFH_Exposure/Mother:Post:WFH_Exposure (a classic Moulton
# problem: errors are correlated within a cell via the shared exposure value and shared unobserved
# cell shocks, and individual-level clustering doesn't see that correlation at all). Clustering on
# the cell itself is the correct level for a shift-share regressor assigned at that granularity.
# ~210 clusters is above the usual >=40-50 rule of thumb for asymptotic cluster-robust inference,
# but still not large -- a small-cluster correction (e.g. wild-cluster bootstrap via fwildclusterboot)
# would need a new dependency and is flagged separately rather than added here.
cell_cluster_formula <- as.formula(paste("~", paste(cell_fe_vars, collapse = "^")))

# Mother:GilNK, added 2026-09-11 per docs/decisions/age-balance-robustness-chain.md's real-data
# finding: GilNK is imbalanced between Mother==1/0 in the pre-period, with the gap's SIZE varying
# by WFH_Exposure quartile -- an additive GilNK term can't correct for an imbalance that itself
# varies with the regressor of interest. Confirmed against real data (robustness/
# age_balance_robustness.R's run_ddd_age_interacted()) that adding this term does NOT change the
# Mother:Post:WFH_Exposure conclusion (stays insignificant, similar magnitude either way) -- so
# this isn't rescuing or overturning the WFH-mechanism result, it's a distinct, independently real
# finding this term surfaces: once included, the base Mother effect and Mother:GilNK terms
# themselves become significant and age-increasing in the cell-FE spec, which the purely-additive
# GilNK control had been masking. In Spec 2, GilNK's own main effect is absorbed into the cell FE,
# but Mother:GilNK is NOT collinear with it (the FE groups by GilNK^TeudaGvoha^MachozMegurim
# jointly, not by an individual's own Mother status within that cell), so it still adds
# non-redundant information there.
ddd_primary_additive <- feols(
  as.formula(paste("Employed ~ Mother * Post * WFH_Exposure + Mother:GilNK +",
                    paste(DEFAULT_CONTROLS, collapse = " + "))),
  data = ddd_df, cluster = cell_cluster_formula
)
ddd_primary_fe <- feols(
  as.formula(paste("Employed ~ Mother * Post * WFH_Exposure + Mother:GilNK +",
                    paste(other_controls, collapse = " + "),
                    "|", paste(cell_fe_vars, collapse = "^"))),
  data = ddd_df, cluster = cell_cluster_formula
)
check_for_dropped_coefficients(ddd_primary_additive, "primary DDD Spec 1 (additive controls)")
# WFH_Exposure's bare main effect is EXPECTED to drop here -- see the comment above Spec 2's
# formula. Only an additional, unexpected drop should warn.
check_for_dropped_coefficients(ddd_primary_fe, "primary DDD Spec 2 (interacted cell FE)",
                                expected_drops = "WFH_Exposure")
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

# ── 8e. Age-balance robustness chain (docs/decisions/age-balance-robustness-chain.md) ─────────
# Off by default: these are diagnostic/comparison checks layered on top of the primary DDD (8a),
# not a replacement for it -- whether run_ddd_age_interacted()/run_ddd_reweighted() should REPLACE
# 8a as the primary spec is a separate, still-open methodological decision (see the decision memo),
# not something this flag resolves. Previously this whole chain (robustness/balance_test.R,
# age_balance_robustness.R, pretrend_wald_test.R) existed only as unit-tested functions with no
# orchestrator ever calling them against real data -- the age-imbalance claim in
# age_balance_robustness.R's own header comment was asserted, not verified, until this wiring.
# phase2_robustness.R is deliberately NOT wired in here: its run_ddd_weights_check() applies
# MishkalSofi as a feols() weight, which CLAUDE.md requires raising with the user before adding to
# any run, not just before committing its output -- see the decision memo's "Not wired in" section.
RUN_AGE_BALANCE_ROBUSTNESS <- FALSE
if (RUN_AGE_BALANCE_ROBUSTNESS) {
  source(file.path("robustness", "balance_test.R"))
  source(file.path("robustness", "age_balance_robustness.R"))
  source(file.path("robustness", "pretrend_wald_test.R"))

  message("Running Phase 1b covariate-balance test (Mother vs. non-Mother, by WFH_Exposure quartile)...")
  balance_check <- run_balance_test(cleaned_df, exposure_cells = exposure_cells)

  message("Diagnosing GilNK (age-group) imbalance by WFH_Exposure quartile...")
  age_balance_diag <- diagnose_gilnk_by_quartile(cleaned_df, exposure_cells)

  message("Running age-interacted comparison spec (Mother:GilNK added to the primary DDD)...")
  ddd_age_interacted <- run_ddd_age_interacted(cleaned_df, exposure_cells)

  message("Running GilNK-reweighted comparison spec (pre-period raking weights)...")
  ddd_reweighted <- run_ddd_reweighted(cleaned_df, exposure_cells)

  message("Running joint Wald test on pre-2020 Mother:year pre-trend coefficients...")
  pretrend_wald <- run_pretrend_joint_test(diagnostics_results$pretrend_model)
}

# ── 8f. Null-vs-power audit (docs/decisions/null-vs-power-audit.md) ───────────────────────────
# Off by default, diagnostic layered on top of the primary DDD (8a), not a replacement for it --
# same framing as 8e. Exists to answer a question the null Mother:Post:WFH_Exposure result alone
# can't: is this design well-powered enough to detect a plausible effect, or is the null
# uninformative? Two checks: (1) does WFH_Exposure actually predict realized WFH_RefWeek at all
# once measurable (Post==1) -- the shift-share design's core relevance assumption, asserted in
# docs/decisions/calibrated-exposure-and-cell-ddd.md but never tested directly against real WFH
# data until now; (2) the closed-form minimum detectable effect for both primary-DDD specs, so the
# observed point estimates (0.103 additive / 0.131 cell-FE) can be read against how small a true
# effect this design could even reliably detect.
RUN_NULL_VS_POWER_AUDIT <- FALSE
if (RUN_NULL_VS_POWER_AUDIT) {
  message("Checking WFH_Exposure's first-stage relevance against realized WFH_RefWeek...")
  wfh_first_stage <- check_wfh_first_stage_relevance(ddd_df)

  message("Computing minimum detectable effect for the primary DDD's triple interaction...")
  baseline_employment_rate <- mean(ddd_df$Employed, na.rm = TRUE)
  mde_additive <- compute_ddd_mde(ddd_primary_additive, baseline_rate = baseline_employment_rate)
  mde_fe       <- compute_ddd_mde(ddd_primary_fe, baseline_rate = baseline_employment_rate)
}

# ── 9. Export results ─────────────────────────────────────────────────────────
# idpuf_panel_check is deliberately NOT included here: its idpuf_years/idpuf_periods tables are
# keyed by individual IDPUF, which is closer to raw identifiable microdata than the aggregate
# tables everything else in this list produces -- per this project's disclosure-risk convention
# (CLAUDE.md, Checkpoint 9), only its console-printed summary counts are surfaced, not a
# persisted per-person roster.
results_to_export <- list(
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
)

if (RUN_AGE_BALANCE_ROBUSTNESS) {
  # Only the aggregate pieces of each result -- balance_check$pre_df / age_balance_diag$pre_df are
  # row-level (one row per surveyed person) and deliberately excluded, same disclosure-risk logic
  # as idpuf_panel_check above.
  results_to_export$age_balance_robustness <- list(
    balance_test = list(
      gilnk_balance     = balance_check$gilnk_balance,
      gilnk_ttests      = balance_check$gilnk_ttests,
      cat_distributions = balance_check$cat_distributions,
      cat_chisq         = balance_check$cat_chisq
    ),
    age_imbalance_by_quartile = age_balance_diag$gap_by_quartile,
    ddd_age_interacted = etable(
      ddd_age_interacted$additive, ddd_age_interacted$fe,
      headers = c("Age-interacted: additive", "Age-interacted: cell FE"), digits = 4
    ),
    ddd_reweighted = etable(
      ddd_reweighted$additive, ddd_reweighted$fe,
      headers = c("Reweighted: additive", "Reweighted: cell FE"), digits = 4
    )
  )
}

if (RUN_NULL_VS_POWER_AUDIT) {
  results_to_export$null_vs_power_audit <- list(
    wfh_first_stage_table = wfh_first_stage$table,
    mde_additive           = mde_additive,
    mde_fe                 = mde_fe
  )
}

message("Exporting results to outputs/...")
export_all_results(results_to_export)
