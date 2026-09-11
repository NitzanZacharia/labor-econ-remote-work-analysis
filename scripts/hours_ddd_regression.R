# hours_ddd_regression.R
# Intensive-margin counterpart to ddd_regression.R's Model 1: same triple-interaction DDD
# (Mother*Post*WFH_Exposure), but on the hours-worked outcome instead of employment, and
# restricted (by construction) to the Employed == 1 subsample. See
# docs/decisions/hours-ddd-pivot.md for the full rationale.
#
# The exposure regressor here is the PURE occupation-level measure (exposure_calibrated's
# wfh_exposure_calibrated, joined by MishlachYad_ISCO_08_2 -- ~40 ISCO-2 groups), not the
# demographic-cell-based WFH_Exposure the extensive-margin primary DDD uses. That measure was
# rejected for the extensive margin specifically because occupation is undefined for the
# non-employed, and Employed (the extensive DDD's own outcome) would then be conditioned on itself
# (docs/decisions/exposure-cell-granularity-fix.md). WorkHoursCont is already, by construction,
# undefined for anyone with Employed != 1 (data_processing.R:184-193) -- conditioning the hours
# regression on employment is baked into the question itself, not introduced by this exposure
# choice. Dropping non-employed rows still introduces a real selection-on-a-mediator problem for
# the hours estimate (if WFH differentially pulls marginal mothers into employment, the post-period
# employed-mother sample isn't compositionally comparable to the pre-period one) -- that's bounded
# separately by hours_ddd_lee_bounds.R's run_hours_ddd_lee_bounds(), run alongside this point
# estimate, not instead of it.
#
# Unlike run_ddd_regression() (ddd_regression.R), this does NOT include a second-stage
# occupation-by-occupation mechanism regression -- not requested for this pivot, and the
# triple-interaction coefficient itself is already the object of interest here.
library(tidyverse)
library(fixest)
source(file.path("scripts", "data_processing.R"))
source(file.path("scripts", "ddd_collinearity_diagnostics.R"))

run_hours_ddd_regression <- function(cleaned_df, exposure_index, controls = DEFAULT_CONTROLS) {

  n_employed <- sum(cleaned_df$Employed == 1, na.rm = TRUE)

  # Attach each employed row's occupation-level WFH exposure by joining on the occupation code.
  # inner_join() already drops rows with no occupation code (non-employed, or a disclosure-masked
  # ISCO for the employed) -- the explicit filter(Employed == 1) is kept anyway for readability and
  # as a defensive check, since WorkHoursCont being NA for Employed != 1 rows would otherwise make
  # their exclusion implicit rather than stated.
  df_ddd <- cleaned_df %>%
    filter(Employed == 1) %>%
    inner_join(
      exposure_index %>% select(MishlachYad_ISCO_08_2 = occupation_code, WFH_Exposure = wfh_exposure),
      by = "MishlachYad_ISCO_08_2"
    )

  n_matched <- nrow(df_ddd)
  message(sprintf(
    "run_hours_ddd_regression: %d of %d employed rows (%.1f%%) retained an occupation-level WFH_Exposure match (dropped: disclosure-masked or unmapped ISCO codes).",
    n_matched, n_employed, 100 * n_matched / n_employed
  ))

  rhs_ddd <- paste(
    "Mother*Post*WFH_Exposure",
    paste(controls, collapse = " + "),
    sep = " + "
  )
  formula_ddd <- as.formula(paste("WorkHoursCont ~", rhs_ddd))
  # Same Moulton reasoning as ddd_regression.R's run_ddd_regression(): WFH_Exposure is assigned at
  # the occupation level (~40 ISCO-2 groups), not the individual -- cluster on the occupation code,
  # the level the regressor of interest actually varies at, not IDPUF.
  reg_ddd <- feols(formula_ddd, data = df_ddd, cluster = ~MishlachYad_ISCO_08_2)
  check_for_dropped_coefficients(reg_ddd, "run_hours_ddd_regression()'s triple interaction")

  table_ddd <- etable(reg_ddd, headers = c("WorkHoursCont (hours DDD)"), digits = 4)
  print(table_ddd)

  invisible(list(
    table      = table_ddd,
    model      = reg_ddd,
    n_employed = n_employed,
    n_matched  = n_matched
  ))
}
