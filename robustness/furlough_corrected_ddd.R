# furlough_corrected_ddd.R
# Corrected-outcome comparison specs for the Furloughed/Employed_strict correction
# (data_processing.R's derivation comment, docs/decisions/furlough-employed-contamination.md).
# Does NOT modify Employed anywhere, does NOT modify main.R's primary DDD spec -- Employed_strict is
# a new column, run only in these explicitly-added comparison specs, per CLAUDE.md's "don't
# redefine a shared variable in place" convention. Two functions:
#
#   run_basic_reg_furlough_corrected()    -- the simplest, cheapest, most transparent check: does
#     the correction move the plain Mother*Post 2x2 DiD at all?
#   run_primary_ddd_furlough_corrected()  -- reruns main.R's exact primary-DDD Spec 1/Spec 2
#     triple-interaction formulas (Employed ~ Mother*Post*WFH_Exposure + Mother:GilNK + controls,
#     cell-clustered) with Employed_strict swapped in for Employed.
library(tidyverse)
library(fixest)
source(file.path("scripts", "data_processing.R"))
source(file.path("scripts", "basic_regression.R"))
source(file.path("scripts", "ddd_collinearity_diagnostics.R"))

run_basic_reg_furlough_corrected <- function(cleaned_df) {
  message("basic_reg(): original Employed...")
  res_original <- basic_reg(cleaned_df)

  message("basic_reg(): Employed_strict (furlough-corrected)...")
  df_strict <- cleaned_df %>% mutate(Employed = Employed_strict)
  res_strict <- basic_reg(df_strict)

  comparison_table <- etable(
    res_original$models$employed, res_strict$models$employed,
    headers = c("Employed (original)", "Employed_strict (furlough-corrected)"), digits = 4
  )
  print(comparison_table)

  invisible(list(original = res_original, strict = res_strict, table = comparison_table))
}

run_primary_ddd_furlough_corrected <- function(cleaned_df, exposure_cells,
                                                ddd_primary_additive, ddd_primary_fe,
                                                controls = DEFAULT_CONTROLS) {
  cell_fe_vars   <- c("GilNK", "TeudaGvoha", "MachozMegurim")
  other_controls <- setdiff(controls, cell_fe_vars)
  cell_cluster_formula <- as.formula(paste("~", paste(cell_fe_vars, collapse = "^")))

  # exposure_join_vars derived from exposure_cells' own columns (not hardcoded) -- robust to
  # main.R's exposure_cell_vars changing without this file needing to track it in lockstep, same
  # pattern already used in robustness/balance_test.R and age_balance_robustness.R.
  exposure_join_vars <- setdiff(names(exposure_cells), c("WFH_Exposure", "n_cell"))
  ddd_df <- cleaned_df %>% left_join(exposure_cells, by = exposure_join_vars)

  strict_additive <- feols(
    as.formula(paste("Employed_strict ~ Mother * Post * WFH_Exposure + Mother:GilNK +",
                      paste(controls, collapse = " + "))),
    data = ddd_df, cluster = cell_cluster_formula
  )
  strict_fe <- feols(
    as.formula(paste("Employed_strict ~ Mother * Post * WFH_Exposure + Mother:GilNK +",
                      paste(other_controls, collapse = " + "),
                      "|", paste(cell_fe_vars, collapse = "^"))),
    data = ddd_df, cluster = cell_cluster_formula
  )
  check_for_dropped_coefficients(strict_additive, "furlough-corrected DDD Spec 1 (additive)")
  check_for_dropped_coefficients(strict_fe, "furlough-corrected DDD Spec 2 (cell FE)")

  comparison_table <- etable(
    ddd_primary_additive, strict_additive, ddd_primary_fe, strict_fe,
    headers = c("Spec 1: original", "Spec 1: furlough-corrected",
                "Spec 2: original", "Spec 2: furlough-corrected"),
    digits = 4
  )
  print(comparison_table)

  invisible(list(additive = strict_additive, fe = strict_fe, table = comparison_table))
}
