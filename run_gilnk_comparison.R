# run_gilnk_comparison.R
#
# Standalone entry point to view the two GilNK-imbalance comparison DDD specs
# (age-interacted; GilNK-reweighted, robustness/age_balance_robustness.R) against real data,
# without permanently flipping main.R's RUN_AGE_BALANCE_ROBUSTNESS flag (main.R hardcodes it to
# FALSE on every source(), so pre-setting the variable before sourcing main.R doesn't work).
#
# Rebuilds only what these functions need -- cleaned_df, cleaned_men_for_exposure, and
# exposure_cells -- by mirroring main.R's own construction (§2-3 caching, §8's exposure_calibrated
# / exposure_cells steps) rather than reimplementing it, so the numbers match what main.R's own
# wired-in RUN_AGE_BALANCE_ROBUSTNESS branch would produce. Skips the occupation-level robustness
# DDDs (§8b-8d), which none of the specs below depend on.
#
# Also prints diagnose_gilnk_by_quartile()'s table (the raw imbalance-by-quartile evidence) ahead
# of the three DDD specs, since it's the numbers that motivate looking at them at all.
#
# Runs main.R's §8a primary DDD (unmodified formulas/clustering, copied verbatim -- not
# reimplemented) alongside the two comparison specs so all three sit on an identical sample: same
# ddd_df join, same listwise-deletion exclusions. Comparing primary vs. comparison across two
# separate runs/samples would make it impossible to tell whether a difference in the
# Mother:Post:WFH_Exposure coefficient is coming from the age correction itself or from a sample
# that quietly shifted between runs.
#
# Console output only -- nothing written to outputs/, nothing staged or committed. See
# docs/decisions/age-balance-robustness-chain.md for the methodology and the 2026-09-09 audit this
# reproduces.
#
# Rscript run_gilnk_comparison.R

rm(list = ls())
source(file.path("scripts", "data_processing.R"))
source(file.path("scripts", "validation.R"))
source(file.path("scripts", "wfh_exposure_cells.R"))
source(file.path("robustness", "balance_test.R"))
source(file.path("robustness", "age_balance_robustness.R"))

message("Edit folder_path below if needed!")
folder_path <- "csvs"

load_cached_or_fresh <- function(folder_path, rds_file_path, sex_filter) {
  cache_meta_path      <- paste0(rds_file_path, ".meta.rds")
  data_processing_hash <- unname(tools::md5sum(file.path("scripts", "data_processing.R")))
  cache_is_valid <- file.exists(rds_file_path) && file.exists(cache_meta_path) &&
    identical(readRDS(cache_meta_path)$data_processing_hash, data_processing_hash)

  if (cache_is_valid) {
    message(sprintf("Found saved RDS (%s) -- loading pre-cleaned data...", rds_file_path))
    readRDS(rds_file_path)
  } else {
    message(sprintf("No valid cache for %s -- checking schema drift and loading raw data...", rds_file_path))
    check_schema_drift(folder_path)
    df <- load_and_clean_data(folder_path, sex_filter = sex_filter)
    saveRDS(df, file = rds_file_path)
    saveRDS(list(data_processing_hash = data_processing_hash), file = cache_meta_path)
    df
  }
}

cleaned_df <- load_cached_or_fresh(
  folder_path, file.path(folder_path, "cleaned_df.rds"), sex_filter = "women"
)
validate_cleaned_df(cleaned_df)

cleaned_men_for_exposure <- load_cached_or_fresh(
  folder_path, file.path(folder_path, "cleaned_df_men.rds"), sex_filter = "men"
)

# Same rationale as main.R §8: exposure must not be built from the women-only analysis sample
# alone (see wfh_exposure_index.R's header comment).
exposure_population_df <- bind_rows(cleaned_df, cleaned_men_for_exposure)

exposure_external   <- build_exposure_isco2()
exposure_calibrated <- calibrate_isco_exposure(exposure_population_df, exposure_external)

exposure_cells <- build_exposure_cells(
  exposure_population_df,
  exposure_calibrated %>% select(ISCO2, tele_ext = wfh_exposure_calibrated)
)

# ── Primary DDD (main.R §8a, copied verbatim) ────────────────────────────────────────────────
message("\n=== Primary DDD (main.R §8a: cell-based exposure, calibrated, full sample) ===")
ddd_df <- cleaned_df %>%
  left_join(exposure_cells, by = c("Min", "GilNK", "TeudaGvoha", "MachozMegurim"))

cell_fe_vars   <- c("GilNK", "TeudaGvoha", "MachozMegurim")
other_controls <- setdiff(DEFAULT_CONTROLS, cell_fe_vars)
cell_cluster_formula <- as.formula(paste("~", paste(cell_fe_vars, collapse = "^")))

ddd_primary_additive <- feols(
  as.formula(paste("Employed ~ Mother * Post * WFH_Exposure +",
                    paste(DEFAULT_CONTROLS, collapse = " + "))),
  data = ddd_df, cluster = cell_cluster_formula
)
ddd_primary_fe <- feols(
  as.formula(paste("Employed ~ Mother * Post * WFH_Exposure +",
                    paste(other_controls, collapse = " + "),
                    "|", paste(cell_fe_vars, collapse = "^"))),
  data = ddd_df, cluster = cell_cluster_formula
)
print(etable(
  ddd_primary_additive, ddd_primary_fe,
  headers = c("Primary Spec 1: additive controls", "Primary Spec 2: interacted cell FE"), digits = 4
))

message("\n=== GilNK (age-group) imbalance by WFH_Exposure quartile (pre-period) ===")
age_balance_diag <- diagnose_gilnk_by_quartile(cleaned_df, exposure_cells)

message("\n=== Comparison spec 1: age-interacted (adds Mother:GilNK to the primary DDD) ===")
ddd_age_interacted <- run_ddd_age_interacted(cleaned_df, exposure_cells)

message("\n=== Comparison spec 2: GilNK-reweighted (pre-period raking weights) ===")
ddd_reweighted <- run_ddd_reweighted(cleaned_df, exposure_cells)

message("\n=== Three-way summary: Mother:Post:WFH_Exposure across specs ===")
summary_tbl <- data.frame(
  spec = c("Primary: additive", "Primary: cell FE",
           "Age-interacted: additive", "Age-interacted: cell FE",
           "Reweighted: additive", "Reweighted: cell FE"),
  estimate = c(coef(ddd_primary_additive)["Mother:Post:WFH_Exposure"],
               coef(ddd_primary_fe)["Mother:Post:WFH_Exposure"],
               coef(ddd_age_interacted$additive)["Mother:Post:WFH_Exposure"],
               coef(ddd_age_interacted$fe)["Mother:Post:WFH_Exposure"],
               coef(ddd_reweighted$additive)["Mother:Post:WFH_Exposure"],
               coef(ddd_reweighted$fe)["Mother:Post:WFH_Exposure"]),
  se = c(se(ddd_primary_additive)["Mother:Post:WFH_Exposure"],
         se(ddd_primary_fe)["Mother:Post:WFH_Exposure"],
         se(ddd_age_interacted$additive)["Mother:Post:WFH_Exposure"],
         se(ddd_age_interacted$fe)["Mother:Post:WFH_Exposure"],
         se(ddd_reweighted$additive)["Mother:Post:WFH_Exposure"],
         se(ddd_reweighted$fe)["Mother:Post:WFH_Exposure"]),
  n = c(nobs(ddd_primary_additive), nobs(ddd_primary_fe),
        nobs(ddd_age_interacted$additive), nobs(ddd_age_interacted$fe),
        nobs(ddd_reweighted$additive), nobs(ddd_reweighted$fe))
)
summary_tbl$p_value <- 2 * pnorm(-abs(summary_tbl$estimate / summary_tbl$se))
print(summary_tbl, digits = 4)

message("\nDone. Nothing was written to outputs/ or saved -- copy the console output above if you ",
        "want to keep it (and run it past disclosure review before putting it in a draft).")
