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
source(file.path("scripts", "ddd_exposure_family_wald_test.R"))
source(file.path("scripts", "ddd_exposure_synthesis.R"))
source(file.path("scripts", "ddd_wald_iv_ratio.R"))
source(file.path("scripts", "ddd_wild_cluster_bootstrap.R"))
source(file.path("scripts", "ddd_loco_controls_diagnostics.R"))
source(file.path("scripts", "wfh_first_stage_mother_heterogeneity.R"))
source(file.path("scripts", "intensive_margin_wfh_ddd.R"))
source(file.path("scripts", "furlough_diagnostics.R"))

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

# (d) Pre-period (2017-2019) shift-share exposure by demographic cell, built from the calibrated
# occupation-level score (b). Unlike (a)-(c), this is defined for every row of cleaned_df --
# employed and non-employed alike -- so it's the only one of the four that doesn't condition the
# third difference on Employed, the regression's own outcome. This is the primary exposure measure
# for the causal DDD.
#
# exposure_cell_vars is DELIBERATELY FINER than cell_fe_vars below (adds MatzavMishpachti, Dat,
# BirthContinent -- MatzavMishpachti/Dat are already DEFAULT_CONTROLS; BirthContinent
# (data_processing.R's country-of-birth-by-continent derivation) is not a regression control at
# all, added here specifically because it explains real variance in the underlying occupation
# exposure score itself. All three are pre-period demographic variables observed for everyone
# regardless of employment status, so adding them doesn't reintroduce occupation-level exposure's
# employment-conditioning problem). See docs/decisions/null-vs-power-audit.md for why this matters:
# when the exposure measure was built on EXACTLY cell_fe_vars (the old design), it was collinear
# enough with its own controls/FE that the primary DDD's minimum detectable effect for
# Mother:Post:WFH_Exposure was ~51% of the baseline employment rate -- roughly 4x the actual point
# estimate, meaning the null result was uninformative, not evidence of a true null. Verified against
# real data (docs/decisions/exposure-cell-granularity-fix.md): adding MatzavMishpachti+Dat cut the
# MDE by ~37% (4,580 cells, only 2 below n=100). Adding BirthContinent on top of that (this update)
# cuts it a further ~18% (8,884 cells, median cell size 1,776, only 9 below n=100) -- a different
# mechanism than the first cut: BirthContinent measurably reduces WFH_Exposure's own measurement
# noise (raises its R^2 against the underlying occupation exposure score from 0.322 to 0.375 on the
# pre-period employed population), rather than only decorrelating it from cell_fe_vars.
exposure_cell_vars <- c("Min", "GilNK", "TeudaGvoha", "MachozMegurim", "MatzavMishpachti", "Dat",
                         "BirthContinent")
exposure_cells <- build_exposure_cells(
  exposure_population_df,
  exposure_calibrated %>% select(ISCO2, tele_ext = wfh_exposure_calibrated),
  cell_vars = exposure_cell_vars
)

# ── 8a. Primary DDD: cell-based exposure, defined for the full sample ─────────
# Two specs, reported side by side. cell_fe_vars (Spec 1's additive controls / Spec 2's fixed
# effect) is intentionally COARSER than exposure_cell_vars above -- WFH_Exposure now varies within
# every cell_fe_vars cell (across MatzavMishpachti/Dat/BirthContinent categories), which is what restores
# identifying power for Mother:Post:WFH_Exposure (see the comment above exposure_cells and
# docs/decisions/exposure-cell-granularity-fix.md). Spec 1's WFH_Exposure still carries some
# overlap with cell_fe_vars (it's built partly from those same 3 variables) --
# check_spec1_collinearity() below reports the live R²/VIF/condition number rather than a static
# comment. Spec 2's fully interacted cell FE no longer spans the same partition WFH_Exposure was
# built on, so (verified against real data) WFH_Exposure's bare main effect is NOT dropped by
# collinearity here anymore, unlike the old design where exposure and FE cells were identical.
message("Running primary DDD (cell-based exposure, calibrated, full sample)...")
ddd_df <- cleaned_df %>%
  left_join(exposure_cells, by = exposure_cell_vars)
message(sprintf(
  "Primary DDD join: %d of %d rows unmatched to an exposure cell (WFH_Exposure NA).",
  sum(is.na(ddd_df$WFH_Exposure)), nrow(ddd_df)
))

cell_fe_vars    <- c("GilNK", "TeudaGvoha", "MachozMegurim")
other_controls  <- setdiff(DEFAULT_CONTROLS, cell_fe_vars)

# WFH_Exposure is assigned at exposure_cell_vars's finer granularity (~4,580 distinct cells), not
# at the individual level -- clustering at IDPUF would still understate the true SE on
# WFH_Exposure/Mother:WFH_Exposure/Post:WFH_Exposure/Mother:Post:WFH_Exposure (a classic Moulton
# problem: errors are correlated within a shift-share cell via the shared exposure value and shared
# unobserved cell shocks, and individual-level clustering doesn't see that correlation at all).
# Clustering here is on the COARSER cell_fe_vars grouping (~210 distinct cells) rather than the
# exposure cell itself -- clustering coarser than the level a regressor is assigned at is still
# valid (and conservative, if anything) for the same Moulton reasoning, since every cell_fe_vars
# group is a union of one or more exposure cells. ~210 clusters is above the usual >=40-50 rule of
# thumb for asymptotic cluster-robust inference, but still not large -- a small-cluster correction
# (e.g. wild-cluster bootstrap via fwildclusterboot) would need a new dependency and is flagged
# separately rather than added here.
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
# Unlike the old design (exposure_cell_vars == cell_fe_vars exactly), WFH_Exposure's bare main
# effect is NOT expected to drop here anymore -- exposure_cell_vars is now finer than cell_fe_vars
# (see the comment above exposure_cells), so WFH_Exposure varies within every cell_fe_vars FE cell
# and is no longer exactly collinear with the FE. Verified against real data
# (docs/decisions/exposure-cell-granularity-fix.md); no expected_drops here means any drop at all
# --including WFH_Exposure's-- now triggers a warning, which is the point.
check_for_dropped_coefficients(ddd_primary_fe, "primary DDD Spec 2 (interacted cell FE)")
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

# ── Small-cluster correction for the 3 occupation-level robustness DDDs (~40 ISCO-2 clusters) ──
# Audit finding E3: these specs' cluster-robust SEs get no small-cluster adjustment, unlike the
# ~210-cluster primary DDD's already-documented follow-up. Wild-cluster bootstrap (fwildclusterboot)
# is the standard correction. Wrapped in tryCatch, matching this codebase's existing convention for
# a diagnostic that shouldn't take down the whole run (see wfh_exposure_cells.R's
# calibrate_isco_exposure() / gender_placebo.R's fit() helper) -- in particular, this degrades
# gracefully (NULL + a message) if fwildclusterboot isn't installed, rather than erroring main.R.
run_wcb_safely <- function(model, label) {
  tryCatch(
    run_wild_cluster_bootstrap(model, "MishlachYad_ISCO_08_2"),
    error = function(e) {
      message("Wild-cluster bootstrap skipped for ", label, ": ", conditionMessage(e))
      NULL
    }
  )
}
message("Running wild-cluster bootstrap on occupation-level DDDs (~40 clusters, small-cluster correction)...")
wcb_calibrated <- run_wcb_safely(ddd_calibrated$models$ddd, "calibrated occupation-level DDD")
wcb_external    <- run_wcb_safely(ddd_external$models$ddd, "external occupation-level DDD")
wcb_realized    <- run_wcb_safely(ddd_realized$models$ddd, "realized occupation-level DDD")

# ── Gender DDD placebo (mirrors the primary DDD exactly, male subsample) ──────────────────────
# run_gender_ddd_placebo() (scripts/gender_placebo.R) has existed since the age-balance chain was
# added but was never actually called against real data anywhere -- only the older, simpler
# Mother:Post basic_reg() placebo (run_gender_placebo()) has a documented real-data result. This
# runs the DDD-mirroring placebo directly, reusing cleaned_men_for_exposure/exposure_calibrated
# already built above for the exposure measures themselves.
message("Running gender DDD placebo (male subsample, mirrors the primary DDD spec exactly)...")
gender_ddd_placebo <- run_gender_ddd_placebo(cleaned_men_for_exposure, exposure_calibrated)
gender_ddd_placebo_table <- NULL
if (!is.null(gender_ddd_placebo)) {
  models_ok <- Filter(Negate(is.null), gender_ddd_placebo$models)
  if (length(models_ok) > 0) {
    hdrs <- c(additive = "Placebo Spec 1: additive controls",
              fe       = "Placebo Spec 2: interacted cell FE")[names(models_ok)]
    gender_ddd_placebo_table <- do.call(etable, c(models_ok, list(headers = unname(hdrs), digits = 4)))
  }
}

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
RUN_AGE_BALANCE_ROBUSTNESS <- TRUE
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
  wfh_first_stage <- check_wfh_first_stage_relevance(ddd_df, cell_fe_vars = cell_fe_vars)

  message("Computing minimum detectable effect for the primary DDD's triple interaction...")
  baseline_employment_rate <- mean(ddd_df$Employed, na.rm = TRUE)
  mde_additive <- compute_ddd_mde(ddd_primary_additive, baseline_rate = baseline_employment_rate)
  mde_fe       <- compute_ddd_mde(ddd_primary_fe, baseline_rate = baseline_employment_rate)
}

# ── 8g. Exposure-interaction power diagnostics (family Wald test + cross-measure synthesis) ────
# Off by default, diagnostic layered on top of the primary DDD (8a) and robustness DDDs (8b-8d),
# not a replacement for either -- same framing as 8e/8f. Three distinct questions neither the
# per-coefficient tables nor the MDE audit (8f) answer on their own:
# (1) run_ddd_exposure_family_wald_test(): is the null on Mother:Post:WFH_Exposure alone masking a
#     jointly-significant signal across the whole {Mother:WFH_Exposure, Post:WFH_Exposure,
#     Mother:Post:WFH_Exposure} family, which shares one correlated WFH_Exposure regressor?
# (2) synthesize_ddd_triple_interaction(): pooling the triple-interaction estimate across all 5
#     already-fitted DDD models (primary additive/FE + the 3 occupation-level robustness specs)
#     via inverse-variance weighting, with Cochran's Q flagging whether that pooling is even valid
#     given each model's different WFH_Exposure proxy and sample (see the function's own header
#     comment for why the naive pooled SE is anti-conservative, not a standalone inference).
# (3) compute_ddd_wald_iv_ratio(): rescales the reduced-form triple interaction by the WFH_Exposure
#     -> WFH_RefWeek first stage, expressing the null in units of "implied effect per unit of
#     actual realized WFH-taking" rather than the diluted cell-level exposure regressor. A
#     row-level 2SLS was considered and rejected (see the function's own header comment):
#     WFH_RefWeek is only non-missing for Post==1 & Employed==1 & AvadBeshavua==1 rows, so using it
#     as an endogenous regressor with Employed as the outcome would leave Employed definitionally 1
#     in the estimation sample -- no outcome variation to explain. This ratio is a reinterpretation
#     of MAGNITUDE, not a statistical-power fix; see the function's own caveats.
RUN_EXPOSURE_POWER_DIAGNOSTICS <- TRUE
if (RUN_EXPOSURE_POWER_DIAGNOSTICS) {
  message("Running joint Wald test on the WFH_Exposure interaction family (primary DDD, both specs)...")
  wald_family_additive <- run_ddd_exposure_family_wald_test(ddd_primary_additive)
  wald_family_fe       <- run_ddd_exposure_family_wald_test(ddd_primary_fe)

  message("Synthesizing Mother:Post:WFH_Exposure across all 5 fitted DDD models...")
  ddd_triple_synthesis <- synthesize_ddd_triple_interaction(list(
    primary_additive    = ddd_primary_additive,
    primary_fe          = ddd_primary_fe,
    occupation_calibrated = ddd_calibrated$models$ddd,
    occupation_external   = ddd_external$models$ddd,
    occupation_realized   = ddd_realized$models$ddd
  ))

  message("Rescaling the primary DDD's triple interaction by the WFH_Exposure first stage...")
  wfh_first_stage  <- check_wfh_first_stage_relevance(ddd_df, cell_fe_vars = cell_fe_vars)
  wald_iv_additive <- compute_ddd_wald_iv_ratio(ddd_primary_additive, wfh_first_stage$level_reg)
  wald_iv_fe       <- compute_ddd_wald_iv_ratio(ddd_primary_fe, wfh_first_stage$level_reg)
}

# ── 8h. Phase 2 specification-robustness checks (two-way clustering, education-sector) ────────
# Off by default, same framing as 8e/8f/8g. robustness/phase2_robustness.R is fully coded and unit-
# tested (three checks: 2a two-way clustering, 2b education-sector transparency, 2c a MishkalSofi
# survey-design-weight comparison) but, unlike the age-balance chain, was never even SOURCED from
# main.R before now -- none of its checks have a documented real-data run anywhere in the repo.
# Only 2a and 2b are run here. 2c (run_ddd_weights_check()) is deliberately excluded: it applies
# MishkalSofi as a feols() weight, which CLAUDE.md requires explicit user sign-off for before any
# run, not just before committing output -- that sign-off has not been given, so 2c stays
# unexecuted, exactly as documented in docs/decisions/age-balance-robustness-chain.md's "Not wired
# in" section for this whole file.
#
# Both checks below are built on prepare_reweighted_ddd_df()'s rake-reweighted baseline (the
# GilNK-imbalance correction from age_balance_robustness.R), not main.R's own primary DDD frame --
# this is a real difference from 8a/8e, not an oversight; see phase2_robustness.R's own header.
RUN_PHASE2_SPEC_ROBUSTNESS <- TRUE
if (RUN_PHASE2_SPEC_ROBUSTNESS) {
  source(file.path("robustness", "phase2_robustness.R"))

  message("Running 2a: one-way vs. two-way (IDPUF + occupation x year) clustering...")
  phase2_twoway <- run_ddd_twoway_cluster(cleaned_df, exposure_cells)
  phase2_twoway_table <- etable(
    phase2_twoway$additive$one_way, phase2_twoway$additive$two_way,
    phase2_twoway$fe$one_way, phase2_twoway$fe$two_way,
    headers = c("Additive: 1-way (IDPUF)", "Additive: 2-way (+occ x year)",
                "FE: 1-way (IDPUF)", "FE: 2-way (+occ x year)"),
    digits = 4
  )

  message("Running 2b: education-sector transparency (ISCO23 exclusion + explicit interaction)...")
  phase2_education <- run_ddd_education_checks(cleaned_df, exposure_cells)
  phase2_education_excl_table <- etable(
    phase2_education$exclude_isco23$additive, phase2_education$exclude_isco23$fe,
    headers = c("Excl. ISCO23: additive", "Excl. ISCO23: cell FE"), digits = 4
  )
  phase2_education_dummy_table <- etable(
    phase2_education$education_dummy$additive, phase2_education$education_dummy$fe,
    headers = c("+EducationSector: additive", "+EducationSector: cell FE"), digits = 4
  )
}

# ── 8i. Leave-one-control-out audit + first-stage Mother heterogeneity ────────────────────────
# Off by default, same framing as 8e-8h. Two checks, both motivated by real-data findings surfaced
# above rather than a speculative sweep:
# (1) run_ddd_leave_one_control_out(): the age-balance chain (8e) already showed GilNK's imbalance
#     was consequential once controlled for differently (Mother:GilNK). robustness/balance_test.R's
#     real-data run (also 8e) shows MatzavMishpachti has an even larger, more quartile-varying
#     imbalance than GilNK ever had -- this checks whether removing it (or any other DEFAULT_CONTROLS
#     member) moves Mother:Post:WFH_Exposure, the non-speculative way to audit "bad controls" (only
#     removes existing controls, never adds a new one).
# (2) check_wfh_first_stage_by_mother(): tests whether WFH_Exposure -> realized WFH is homogeneous
#     across Mother status, on the full Post==1 individual-level sample -- not bottlenecked by the
#     primary DDD's cell-level MDE problem, so this is the best-powered test in the whole diagnostic
#     suite for whether the exposure "dose" itself differs by Mother status.
RUN_LOCO_AND_FIRST_STAGE_HETEROGENEITY <- TRUE
if (RUN_LOCO_AND_FIRST_STAGE_HETEROGENEITY) {
  message("Running leave-one-control-out audit on the primary DDD's Spec 1...")
  loco_controls <- run_ddd_leave_one_control_out(ddd_df, cell_fe_vars = cell_fe_vars)

  message("Checking WFH_Exposure's first-stage relevance BY Mother status (Post==1 only)...")
  wfh_first_stage_by_mother <- check_wfh_first_stage_by_mother(ddd_df, cell_fe_vars = cell_fe_vars)
}

# ── 8j. Subgroup heterogeneity (child age, single-parent status) + intensive-margin WFH DDD ────
# Off by default, same framing as 8e-8i. Three checks:
# (1)/(2) run_ddd_by_child_age()/run_ddd_by_single_parent() (robustness/mother_heterogeneity_
#     robustness.R): the pooled binary Mother indicator averages a mother of a 1-year-old with a
#     mother of a 16-year-old, and a single mother with a partnered one, into one coefficient -- if
#     WFH-driven labor-supply elasticity is concentrated in the highest-need subgroups, that pooling
#     is exactly the kind of masking that would produce today's null. Both split variables
#     (GilYeledTzairMBNK, MisparHorimYechidim) already exist in cleaned_df but were never wired into
#     the DDD before. See the file's own header for the MisparHorimYechidim > 0 "single parent"
#     coding ASSUMPTION (unverified against the CBS codebook -- the raw distribution is printed so
#     it's checkable) and the MDE caveat (each subgroup is smaller than the full mother population,
#     so its MDE is larger than the already-underpowered full-sample one).
# (3) run_intensive_margin_wfh_ddd() (scripts/intensive_margin_wfh_ddd.R): Employed is a 0/1
#     indicator structurally blind to an intensification channel (part-time -> full-time within the
#     same employment spell) -- this tests the WFH-exposure mechanism on WorkHoursCont instead,
#     conditional on Employed==1. Treat a significant result here as suggestive, not final -- see
#     the function's own header on the selection-on-Employed caveat this shares with
#     intensive_margin_lee_bounds.R.
RUN_MOTHER_HETEROGENEITY_AND_INTENSIVE_WFH <- TRUE
if (RUN_MOTHER_HETEROGENEITY_AND_INTENSIVE_WFH) {
  source(file.path("robustness", "mother_heterogeneity_robustness.R"))

  message("Running primary DDD spec by youngest-child age (under 5 vs. 5-17)...")
  ddd_by_child_age <- run_ddd_by_child_age(cleaned_df, exposure_cells)

  message("Running primary DDD spec by single-parent status...")
  ddd_by_single_parent <- run_ddd_by_single_parent(cleaned_df, exposure_cells)

  message("Running WFH-mechanism DDD on the intensive margin (WorkHoursCont, Employed==1)...")
  intensive_wfh_ddd <- run_intensive_margin_wfh_ddd(cleaned_df, exposure_cells)
}

# ── 8k. Furlough-contamination correction (SibaNeedar==9 misclassified as Employed) ───────────
# Off-by-default framing does NOT apply in the usual sense -- unlike 8e-8j, this is a measurement-
# quality correction with real-data-verified contamination concentrated on the Post side of the
# design (2021: 3.11% of Muasak==1 rows are SibaNeedar==9 furloughed; 2023: 1.41%; vs. ~0.1-0.35%
# in 2017-2019 and 0.42% in 2022 -- see data_processing.R's Furloughed/Employed_strict comment and
# docs/decisions/furlough-employed-contamination.md), so it defaults TRUE. Does NOT replace
# Employed anywhere -- Employed_strict is a new column, run only in these explicitly-added
# comparison specs, per CLAUDE.md.
RUN_FURLOUGH_CORRECTION <- TRUE
if (RUN_FURLOUGH_CORRECTION) {
  source(file.path("robustness", "furlough_corrected_ddd.R"))
  # compute_pre_period_quartile_breaks()/assign_wfh_quartile() live in age_balance_robustness.R --
  # sourced independently here (source() is idempotent) so this block doesn't silently break if
  # RUN_AGE_BALANCE_ROBUSTNESS (§8e) is ever turned off.
  source(file.path("robustness", "age_balance_robustness.R"))

  message("Checking furlough incidence (SibaNeedar==9 among Muasak==1)...")
  furlough_quartile_breaks <- compute_pre_period_quartile_breaks(cleaned_df, exposure_cells)
  furlough_df_with_quartile <- assign_wfh_quartile(
    left_join(cleaned_df, exposure_cells, by = exposure_cell_vars), furlough_quartile_breaks
  )
  furlough_incidence <- check_furlough_incidence(cleaned_df, furlough_df_with_quartile)

  message("Rerunning basic_reg() 2x2 DiD with Employed_strict (furlough-corrected)...")
  basic_reg_furlough_corrected <- run_basic_reg_furlough_corrected(cleaned_df)

  message("Rerunning primary DDD Spec 1/Spec 2 with Employed_strict (furlough-corrected)...")
  ddd_furlough_corrected <- run_primary_ddd_furlough_corrected(
    cleaned_df, exposure_cells, ddd_primary_additive, ddd_primary_fe
  )
}

# ── 9. Export results ─────────────────────────────────────────────────────────
# idpuf_panel_check is deliberately NOT included here: its idpuf_years/idpuf_periods tables are
# per-IDPUF, a finer granularity than the aggregate tables everything else in this list produces --
# only its console-printed summary counts are surfaced here, not a persisted per-person roster.
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
  ddd_realized = ddd_realized,
  gender_ddd_placebo = gender_ddd_placebo_table
)

# wcb_* fields (only cluster_robust_se/boot_p/boot_ci) are exported as one-row data frames;
# boot_summary (the raw fwildclusterboot object) is excluded, the same way results_to_export never
# includes a raw fixest/lm model object directly (export_all_results() already skips those on its
# own, but boot_summary isn't of either class, so it's dropped explicitly here instead).
wcb_fields <- c("param", "cluster_var", "cluster_robust_se", "boot_p")
wcb_to_export_df <- function(wcb) {
  if (is.null(wcb)) return(NULL)
  df <- as.data.frame(wcb[wcb_fields])
  df$boot_ci_lower <- wcb$boot_ci[1]
  df$boot_ci_upper <- wcb$boot_ci[2]
  df
}
results_to_export$wild_cluster_bootstrap <- list(
  calibrated = wcb_to_export_df(wcb_calibrated),
  external   = wcb_to_export_df(wcb_external),
  realized   = wcb_to_export_df(wcb_realized)
)

if (RUN_AGE_BALANCE_ROBUSTNESS) {
  # Only the aggregate pieces of each result -- balance_check$pre_df / age_balance_diag$pre_df are
  # row-level (one row per surveyed person) and deliberately excluded, same granularity choice as
  # idpuf_panel_check above.
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
  # compute_ddd_mde() returns a plain scalar list, not a data frame -- export_all_results() only
  # ever exports data frames and ggplots, so mde_additive/mde_fe were silently dropped from
  # outputs/ despite being cited in 3 decision memos. Wrapped as one-row data frames here so they
  # actually reach disk; compute_ddd_mde()'s own contract/tests are untouched.
  mde_fields <- c("coef_name", "point_estimate", "se", "sig_level", "power", "mde", "within_mde")
  results_to_export$null_vs_power_audit <- list(
    wfh_first_stage_table = wfh_first_stage$table,
    mde_additive           = as.data.frame(mde_additive[mde_fields]),
    mde_fe                 = as.data.frame(mde_fe[mde_fields])
  )
}

if (RUN_EXPOSURE_POWER_DIAGNOSTICS) {
  results_to_export$exposure_power_diagnostics <- list(
    wald_family_additive = as.data.frame(wald_family_additive[c("stat", "p", "df1", "df2")]),
    wald_family_fe       = as.data.frame(wald_family_fe[c("stat", "p", "df1", "df2")]),
    triple_synthesis_per_model = ddd_triple_synthesis$per_model,
    triple_synthesis_summary   = data.frame(
      pooled_estimate = ddd_triple_synthesis$pooled_estimate,
      pooled_se       = ddd_triple_synthesis$pooled_se,
      pooled_p        = ddd_triple_synthesis$pooled_p,
      q_stat          = ddd_triple_synthesis$q_stat,
      q_df            = ddd_triple_synthesis$q_df,
      q_p             = ddd_triple_synthesis$q_p,
      heterogeneous   = ddd_triple_synthesis$heterogeneous,
      most_precise_model = ddd_triple_synthesis$most_precise_model
    ),
    wald_iv_ratio = bind_rows(
      additive = as.data.frame(wald_iv_additive[c("rf_estimate", "rf_se", "fs_estimate", "fs_se", "ratio_estimate", "ratio_se", "z", "p")]),
      fe       = as.data.frame(wald_iv_fe[c("rf_estimate", "rf_se", "fs_estimate", "fs_se", "ratio_estimate", "ratio_se", "z", "p")]),
      .id = "spec"
    )
  )
}

if (RUN_PHASE2_SPEC_ROBUSTNESS) {
  results_to_export$phase2_spec_robustness <- list(
    twoway_cluster           = phase2_twoway_table,
    education_exclude_isco23 = phase2_education_excl_table,
    education_dummy          = phase2_education_dummy_table
  )
}

if (RUN_LOCO_AND_FIRST_STAGE_HETEROGENEITY) {
  results_to_export$loco_and_first_stage_heterogeneity <- list(
    loco_controls              = loco_controls$table,
    wfh_first_stage_by_mother  = wfh_first_stage_by_mother$table
  )
}

if (RUN_MOTHER_HETEROGENEITY_AND_INTENSIVE_WFH) {
  results_to_export$mother_heterogeneity_and_intensive_wfh <- list(
    ddd_by_child_age      = list(table = ddd_by_child_age$table, mde = ddd_by_child_age$mde_table),
    ddd_by_single_parent  = list(table = ddd_by_single_parent$table, mde = ddd_by_single_parent$mde_table),
    intensive_wfh_ddd     = intensive_wfh_ddd$table
  )
}

if (RUN_FURLOUGH_CORRECTION) {
  results_to_export$furlough_correction <- list(
    incidence_by_year     = furlough_incidence$by_year,
    incidence_by_quartile = furlough_incidence$by_quartile,
    basic_reg_comparison  = basic_reg_furlough_corrected$table,
    ddd_comparison        = ddd_furlough_corrected$table
  )
}

message("Exporting results to outputs/...")
export_all_results(results_to_export)
