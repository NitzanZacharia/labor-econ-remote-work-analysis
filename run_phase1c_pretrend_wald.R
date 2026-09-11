# run_phase1c_pretrend_wald.R
#
# Standalone entry point reconstructing Phase 1c's saved joint pre-trend Wald test as its own
# artifact. The original run left only csvs/phase1c_pretrend_wald.rds behind -- no committed
# source file produced it. Reconstructed from the cached object's structure (list(wald,
# pretrend_table), where `wald` is run_pretrend_joint_test()'s return value and `pretrend_table`
# is run_diagnostics()'s own etable output -- see robustness/pretrend_wald_test.R and
# scripts/Diagnostics.R) -- see run_mishkalsofi_check.R's header for the same provenance note
# applied to a different cache.
#
# run_diagnostics() draws an event-study plot to whatever graphics device is active (see its own
# header comment); redirected to a null device here (the same pattern as
# tests/testthat/helper-setup.R's with_null_device()) so this script doesn't leak an
# auto-numbered Rplots*.pdf into the repo root or write to outputs/.
#
# Console output only, plus the one saved artifact this script exists to reconstruct
# (csvs/phase1c_pretrend_wald.rds) -- nothing written to outputs/.
#
# Rscript run_phase1c_pretrend_wald.R

rm(list = ls())
source(file.path("scripts", "data_processing.R"))
source(file.path("scripts", "validation.R"))
source(file.path("scripts", "Diagnostics.R"))
source(file.path("robustness", "pretrend_wald_test.R"))
library(fixest)

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

grDevices::pdf(file = nullfile())
diagnostics_results <- run_diagnostics(cleaned_df)
grDevices::dev.off()

wald_result <- run_pretrend_joint_test(diagnostics_results$pretrend_model)

result <- list(wald = wald_result, pretrend_table = diagnostics_results$pretrend_table)
saveRDS(result, file.path(folder_path, "phase1c_pretrend_wald.rds"))

message("\nDone. Console output above; the results list was also saved to ",
        file.path(folder_path, "phase1c_pretrend_wald.rds"),
        " -- run this past disclosure review before putting it in a draft.")
