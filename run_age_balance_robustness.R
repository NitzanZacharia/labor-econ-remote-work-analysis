# run_age_balance_robustness.R
#
# Standalone entry point reconstructing the saved age-balance robustness chain
# (robustness/age_balance_robustness.R) as its own artifact. The original run left only
# csvs/age_balance_robustness_results.rds behind -- no committed source file produced it.
# Reconstructed from the cached object's structure (list(diag, interacted, reweighted), matching
# diagnose_gilnk_by_quartile() / run_ddd_age_interacted() / run_ddd_reweighted()'s own return
# values exactly) -- see run_mishkalsofi_check.R's header for the same provenance note applied to
# a different cache.
#
# This duplicates run_gilnk_comparison.R's data-loading/exposure-building setup and its three
# comparison-spec calls, but SAVES the results instead of only printing them -- run_gilnk_comparison.R
# is deliberately console-only (see its own header) and is left unmodified.
#
# Console output only, plus the one saved artifact this script exists to reconstruct
# (csvs/age_balance_robustness_results.rds) -- nothing written to outputs/.
#
# Rscript run_age_balance_robustness.R

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

exposure_population_df <- bind_rows(cleaned_df, cleaned_men_for_exposure)

exposure_external   <- build_exposure_isco2()
exposure_calibrated <- calibrate_isco_exposure(exposure_population_df, exposure_external)

exposure_cells <- build_exposure_cells(
  exposure_population_df,
  exposure_calibrated %>% select(ISCO2, tele_ext = wfh_exposure_calibrated)
)

message("\n=== GilNK (age-group) imbalance by WFH_Exposure quartile (pre-period) ===")
diag <- diagnose_gilnk_by_quartile(cleaned_df, exposure_cells)

message("\n=== Comparison spec 1: age-interacted (adds Mother:GilNK to the primary DDD) ===")
interacted <- run_ddd_age_interacted(cleaned_df, exposure_cells)

message("\n=== Comparison spec 2: GilNK-reweighted (pre-period raking weights) ===")
reweighted <- run_ddd_reweighted(cleaned_df, exposure_cells)

result <- list(diag = diag, interacted = interacted, reweighted = reweighted)
saveRDS(result, file.path(folder_path, "age_balance_robustness_results.rds"))

message("\nDone. Console output above; the results list was also saved to ",
        file.path(folder_path, "age_balance_robustness_results.rds"),
        " -- run this past disclosure review before putting it in a draft.")
