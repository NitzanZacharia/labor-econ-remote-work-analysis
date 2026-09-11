# run_mishkalsofi_check.R
#
# Standalone entry point reconstructing an ad-hoc sensitivity check for the scope decision
# recorded in README.md's "Known limitations": survey weights (MishkalSofi) are deliberately not
# applied in any outcome regression in this repo. This script asks what would change if they were,
# without altering that decision or any production script.
#
# The original run of this check left only its console output cached as
# csvs/mishkalsofi_check_results.rds (2026-09-08) -- no source file was ever committed. This
# reconstructs that script from the cached object's structure (list(redundancy, n_eff, deff,
# unweighted, msweighted)) so the check is reproducible and reviewable going forward.
#
# What it checks:
#   1. Redundancy: is MishkalSofi predictable from the regressors already in the model
#      (Mother, WFH_Exposure, DEFAULT_CONTROLS)? log(MishkalSofi) ~ those regressors, via lm().
#      A high R^2 would mean the weight is close to redundant with existing controls; a low one
#      (as found: ~0.09) means it isn't -- weighting could still matter.
#   2. Design effect: Kish's effective sample size (n_eff = (sum w)^2 / sum(w^2)) and design
#      effect (deff = n / n_eff) for MishkalSofi across the DDD analysis sample -- how much
#      precision the weight variability alone costs, independent of any regression.
#   3. Primary DDD sensitivity: main.R's Sec8a primary DDD specs (additive controls; interacted
#      cell FE), unweighted vs. re-estimated with weights = ~MishkalSofi, to see whether the
#      Mother:Post:WFH_Exposure estimate is sensitive to weighting.
#
# Mirrors run_gilnk_comparison.R's construction of cleaned_df / cleaned_men_for_exposure /
# exposure_cells (same caching, same Sec2-3/Sec8 steps) so the sample here matches main.R's own
# primary DDD sample exactly -- not a separately-drifted one.
#
# Console output only -- nothing written to outputs/. The one artifact this produces is the
# reconstructed results/mishkalsofi_check_results.rds cache (an untracked, gitignored-by-*.rds
# convention working file, not a reviewed output), so a future run can be diffed against the
# original without re-deriving it from raw data.
#
# Rscript run_mishkalsofi_check.R

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

# ── 1. Redundancy: is MishkalSofi predictable from the model's own regressors? ─────────────────
message("\n=== Redundancy: log(MishkalSofi) ~ Mother + WFH_Exposure + DEFAULT_CONTROLS ===")
redundancy <- lm(
  as.formula(paste("log(MishkalSofi) ~ Mother + WFH_Exposure +",
                    paste(DEFAULT_CONTROLS, collapse = " + "))),
  data = ddd_df
)
print(summary(redundancy))

# ── 2. Design effect: Kish's effective sample size for MishkalSofi ─────────────────────────────
message("\n=== Design effect: Kish's n_eff and deff for MishkalSofi ===")
w     <- ddd_df$MishkalSofi[!is.na(ddd_df$MishkalSofi)]
n     <- length(w)
n_eff <- sum(w)^2 / sum(w^2)
deff  <- n / n_eff
cat(sprintf("n = %d, n_eff = %.0f, deff = %.4f\n", n, n_eff, deff))

# ── 3. Primary DDD: unweighted vs. MishkalSofi-weighted ────────────────────────────────────────
message("\n=== Primary DDD (main.R Sec8a), unweighted ===")
unweighted <- list(
  additive = feols(
    as.formula(paste("Employed ~ Mother * Post * WFH_Exposure +",
                      paste(DEFAULT_CONTROLS, collapse = " + "))),
    data = ddd_df, cluster = cell_cluster_formula
  ),
  fe = feols(
    as.formula(paste("Employed ~ Mother * Post * WFH_Exposure +",
                      paste(other_controls, collapse = " + "),
                      "|", paste(cell_fe_vars, collapse = "^"))),
    data = ddd_df, cluster = cell_cluster_formula
  )
)
print(etable(unweighted$additive, unweighted$fe,
             headers = c("Unweighted: additive", "Unweighted: cell FE"), digits = 4))

message("\n=== Primary DDD (main.R Sec8a), weighted by MishkalSofi ===")
msweighted <- list(
  additive = feols(
    as.formula(paste("Employed ~ Mother * Post * WFH_Exposure +",
                      paste(DEFAULT_CONTROLS, collapse = " + "))),
    data = ddd_df, cluster = cell_cluster_formula, weights = ~MishkalSofi
  ),
  fe = feols(
    as.formula(paste("Employed ~ Mother * Post * WFH_Exposure +",
                      paste(other_controls, collapse = " + "),
                      "|", paste(cell_fe_vars, collapse = "^"))),
    data = ddd_df, cluster = cell_cluster_formula, weights = ~MishkalSofi
  )
)
print(etable(msweighted$additive, msweighted$fe,
             headers = c("MishkalSofi-weighted: additive", "MishkalSofi-weighted: cell FE"), digits = 4))

message("\n=== Mother:Post:WFH_Exposure across weighting choices ===")
summary_tbl <- data.frame(
  spec = c("Unweighted: additive", "Unweighted: cell FE",
           "MishkalSofi-weighted: additive", "MishkalSofi-weighted: cell FE"),
  estimate = c(coef(unweighted$additive)["Mother:Post:WFH_Exposure"],
               coef(unweighted$fe)["Mother:Post:WFH_Exposure"],
               coef(msweighted$additive)["Mother:Post:WFH_Exposure"],
               coef(msweighted$fe)["Mother:Post:WFH_Exposure"]),
  se = c(se(unweighted$additive)["Mother:Post:WFH_Exposure"],
         se(unweighted$fe)["Mother:Post:WFH_Exposure"],
         se(msweighted$additive)["Mother:Post:WFH_Exposure"],
         se(msweighted$fe)["Mother:Post:WFH_Exposure"]),
  n = c(nobs(unweighted$additive), nobs(unweighted$fe),
        nobs(msweighted$additive), nobs(msweighted$fe))
)
summary_tbl$p_value <- 2 * pnorm(-abs(summary_tbl$estimate / summary_tbl$se))
print(summary_tbl, digits = 4)

results <- list(
  redundancy = redundancy,
  n_eff      = n_eff,
  deff       = deff,
  unweighted = unweighted,
  msweighted = msweighted
)
saveRDS(results, file.path(folder_path, "mishkalsofi_check_results.rds"))

message("\nDone. Console output above; the results list was also saved to ",
        file.path(folder_path, "mishkalsofi_check_results.rds"),
        " -- run this past disclosure review before putting it in a draft.")
