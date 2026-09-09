# ddd_collinearity_diagnostics.R
# Runtime collinearity diagnostic for main.R's primary DDD Spec 1 (additive controls), refreshing
# the two headline stats previously asserted only as a static, hardcoded comment in main.R (74.5%
# of WFH_Exposure's variance explained by GilNK+TeudaGvoha+MachozMegurim alone; design-matrix
# condition number 267.8) directly from the fitted data on every run, so they can't silently go
# stale as the underlying microdata composition changes (new survey years, sample restrictions,
# etc.). Spec 2 (main.R's interacted-cell-FE spec) is the actual fix for this collinearity -- this
# function only measures and reports how bad Spec 1's collinearity is, it doesn't correct anything.
#
# Base R only (lm(), kappa()) -- deliberately avoids adding car as a new dependency (CLAUDE.md:
# flag new dependencies before adding). car::vif() additionally computes a generalized VIF (GVIF)
# for multi-level factors, correcting for the fact that a naive per-dummy-column VIF overstates
# collinearity purely from a factor's own dummy coding -- not needed here, since the only VIF this
# reports is WFH_Exposure's own (a single numeric column, where naive and generalized VIF coincide).
library(tidyverse)

check_spec1_collinearity <- function(ddd_df, cell_fe_vars, controls) {

  # WFH_Exposure's own R^2 (and implied VIF) on the cell-defining variables -- directly reproduces
  # the "74.5% of its variance is explained by..." claim in main.R's comment.
  cell_var_formula <- as.formula(paste("WFH_Exposure ~", paste(cell_fe_vars, collapse = " + ")))
  r2_wfh_exposure_on_cells <- summary(lm(cell_var_formula, data = ddd_df))$r.squared
  vif_wfh_exposure <- 1 / (1 - r2_wfh_exposure_on_cells)

  # Full Spec 1 design-matrix condition number -- reproduces the "condition number 267.8" claim.
  # model.frame()'s na.action = na.omit mirrors feols()'s own listwise deletion, so this is
  # computed on exactly the rows Spec 1 would actually be fit on.
  spec1_rhs <- paste("~ Mother * Post * WFH_Exposure +", paste(controls, collapse = " + "))
  spec1_mf  <- model.frame(as.formula(spec1_rhs), data = ddd_df, na.action = na.omit)
  spec1_X   <- model.matrix(attr(spec1_mf, "terms"), spec1_mf)
  condition_number <- kappa(spec1_X, exact = TRUE)

  message(sprintf(
    paste0(
      "check_spec1_collinearity: WFH_Exposure's own R^2 on (%s) = %.3f (VIF = %.1f); Spec 1's ",
      "design-matrix condition number = %.1f."
    ),
    paste(cell_fe_vars, collapse = " + "), r2_wfh_exposure_on_cells, vif_wfh_exposure,
    condition_number
  ))

  invisible(list(
    r2_wfh_exposure_on_cells = r2_wfh_exposure_on_cells,
    vif_wfh_exposure         = vif_wfh_exposure,
    condition_number         = condition_number
  ))
}
