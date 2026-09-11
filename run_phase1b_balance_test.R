# run_phase1b_balance_test.R
#
# Standalone entry point reconstructing Phase 1b's saved covariate-balance-test run as its own
# artifact. The original run left only csvs/phase1b_balance_test.rds behind -- no committed source
# file produced it. Reconstructed from the cached object's structure (list(pre_df, gilnk_balance,
# gilnk_ttests, cat_distributions, cat_chisq), matching run_balance_test()'s own return value
# exactly -- see robustness/balance_test.R) -- see run_mishkalsofi_check.R's header for the same
# provenance note applied to a different cache.
#
# The cached pre_df has 201,388 rows, matching age_balance_robustness_results.rds's own pre_df
# exactly -- both were built against the SAME pooled (women+men) exposure_cells, not
# run_balance_test()'s own un-pooled fallback (which would build exposure_cells from cleaned_df
# alone). So this script mirrors run_gilnk_comparison.R's pooled construction and passes
# exposure_cells in explicitly, rather than relying on run_balance_test()'s default.
#
# Console output only, plus the one saved artifact this script exists to reconstruct
# (csvs/phase1b_balance_test.rds) -- nothing written to outputs/.
#
# Rscript run_phase1b_balance_test.R

rm(list = ls())
source(file.path("scripts", "data_processing.R"))
source(file.path("scripts", "validation.R"))
source(file.path("scripts", "wfh_exposure_cells.R"))
source(file.path("robustness", "balance_test.R"))

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

result <- run_balance_test(cleaned_df, exposure_cells = exposure_cells)

saveRDS(result, file.path(folder_path, "phase1b_balance_test.rds"))

message("\nDone. Console output above; the results list was also saved to ",
        file.path(folder_path, "phase1b_balance_test.rds"),
        " -- run this past disclosure review before putting it in a draft.")
