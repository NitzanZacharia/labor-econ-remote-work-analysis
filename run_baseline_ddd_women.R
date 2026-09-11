# run_baseline_ddd_women.R
#
# Standalone entry point reconstructing the primary cell-based DDD (main.R Sec8a: additive
# controls / interacted cell FE, women only) as its own saved artifact. The original run left only
# csvs/baseline_ddd_women.rds behind -- no committed source file produced it. Reconstructed from
# the cached object's structure (list(additive, fe), formulas matching main.R's Sec8a exactly) --
# see run_mishkalsofi_check.R's header for the same provenance note applied to a different cache.
#
# Mirrors run_gilnk_comparison.R's construction of cleaned_df / cleaned_men_for_exposure /
# exposure_cells (same caching, same Sec2-3/Sec8 steps), then fits only the primary spec -- the
# age-interacted/reweighted comparison specs live in run_age_balance_robustness.R instead.
#
# Console output only, plus the one saved artifact this script exists to reconstruct
# (csvs/baseline_ddd_women.rds) -- nothing written to outputs/.
#
# Rscript run_baseline_ddd_women.R

rm(list = ls())
source(file.path("scripts", "data_processing.R"))
source(file.path("scripts", "validation.R"))
source(file.path("scripts", "wfh_exposure_cells.R"))
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

cleaned_men_for_exposure <- load_cached_or_fresh(
  folder_path, file.path(folder_path, "cleaned_df_men.rds"), sex_filter = "men"
)

# Same rationale as main.R Sec8: exposure must not be built from the women-only analysis sample
# alone (see wfh_exposure_index.R's header comment).
exposure_population_df <- bind_rows(cleaned_df, cleaned_men_for_exposure)

exposure_external   <- build_exposure_isco2()
exposure_calibrated <- calibrate_isco_exposure(exposure_population_df, exposure_external)

exposure_cells <- build_exposure_cells(
  exposure_population_df,
  exposure_calibrated %>% select(ISCO2, tele_ext = wfh_exposure_calibrated)
)

ddd_df <- cleaned_df %>%
  left_join(exposure_cells, by = c("Min", "GilNK", "TeudaGvoha", "MachozMegurim"))

cell_fe_vars   <- c("GilNK", "TeudaGvoha", "MachozMegurim")
other_controls <- setdiff(DEFAULT_CONTROLS, cell_fe_vars)
cell_cluster_formula <- as.formula(paste("~", paste(cell_fe_vars, collapse = "^")))

message("\n=== Primary DDD (main.R Sec8a: cell-based exposure, calibrated, full sample, women) ===")
additive <- feols(
  as.formula(paste("Employed ~ Mother * Post * WFH_Exposure +",
                    paste(DEFAULT_CONTROLS, collapse = " + "))),
  data = ddd_df, cluster = cell_cluster_formula
)
fe <- feols(
  as.formula(paste("Employed ~ Mother * Post * WFH_Exposure +",
                    paste(other_controls, collapse = " + "),
                    "|", paste(cell_fe_vars, collapse = "^"))),
  data = ddd_df, cluster = cell_cluster_formula
)
print(etable(additive, fe,
             headers = c("Primary Spec 1: additive controls", "Primary Spec 2: interacted cell FE"),
             digits = 4))

saveRDS(list(additive = additive, fe = fe), file.path(folder_path, "baseline_ddd_women.rds"))

message("\nDone. Console output above; the results list was also saved to ",
        file.path(folder_path, "baseline_ddd_women.rds"),
        " -- run this past disclosure review before putting it in a draft.")
