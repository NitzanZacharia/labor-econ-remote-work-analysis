# run_phase2_robustness.R
#
# Standalone entry point reconstructing the saved Phase 2 specification-robustness chain
# (robustness/phase2_robustness.R) as its own artifact. The original run left only
# csvs/phase2_results.rds behind -- no committed source file produced it. Reconstructed from the
# cached object's structure (list(a, b, c), matching run_ddd_twoway_cluster() / 2a,
# run_ddd_education_checks() / 2b, and run_ddd_weights_check() / 2c's own return values exactly)
# -- see run_mishkalsofi_check.R's header for the same provenance note applied to a different
# cache.
#
# All three checks are layered on the SAME re-weighted primary DDD (the GilNK raking weights from
# age_balance_robustness.R), per phase2_robustness.R's own header comment -- so the rake weights
# are built once here and passed into all three, rather than each silently rebuilding its own.
#
# Console output only, plus the one saved artifact this script exists to reconstruct
# (csvs/phase2_results.rds) -- nothing written to outputs/.
#
# Rscript run_phase2_robustness.R

rm(list = ls())
source(file.path("scripts", "data_processing.R"))
source(file.path("scripts", "validation.R"))
source(file.path("scripts", "wfh_exposure_cells.R"))
source(file.path("robustness", "age_balance_robustness.R"))
source(file.path("robustness", "phase2_robustness.R"))

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

rake <- build_gilnk_rake_weights(cleaned_df, exposure_cells)

message("\n=== 2a: two-way clustering (IDPUF + occupation x year) ===")
a <- run_ddd_twoway_cluster(cleaned_df, exposure_cells, rake = rake)

message("\n=== 2b: education-sector transparency (ISCO 23) ===")
b <- run_ddd_education_checks(cleaned_df, exposure_cells, rake = rake)

message("\n=== 2c: survey (design) weight check ===")
c_res <- run_ddd_weights_check(cleaned_df, exposure_cells, rake = rake)

result <- list(a = a, b = b, c = c_res)
saveRDS(result, file.path(folder_path, "phase2_results.rds"))

message("\nDone. Console output above; the results list was also saved to ",
        file.path(folder_path, "phase2_results.rds"),
        " -- run this past disclosure review before putting it in a draft.")
