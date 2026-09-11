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

# Generic safety net for every OTHER feols()/lm() fit in the pipeline: check_spec1_collinearity()
# above only ever covered the primary DDD's Spec 1, by design (it's specifically diagnosing that
# spec's own known WFH_Exposure/cell-control overlap). Nothing previously inspected any other
# fitted model for a silently-dropped-by-collinearity variable.
#
# IMPORTANT, verified empirically against the fixest version this project uses: a collinear
# variable is NOT left in coef() as an NA-valued entry -- fixest removes it from coef() entirely
# (confirmed: feols(y ~ x1 + x2) with x2 <- x1 gives coef() = c("(Intercept)", "x1") only, and
# is.na(coef(m)) is all FALSE). The reliable accessor is the fitted model's own $collin.var, which
# fixest populates with exactly the dropped variable names (NULL/character(0) when nothing was
# dropped). An earlier version of this check used is.na(coef(...)) and would have silently done
# NOTHING -- always worth re-verifying a third-party package's actual behavior instead of assuming
# it from a description.
#
# expected_drops lets a caller name variables it ALREADY KNOWS will be dropped by design (e.g.
# main.R's Spec 2: WFH_Exposure's bare main effect is intentionally collinear with the interacted
# cell FE -- see main.R's own comment and test-primary_ddd_mechanics.R). Only UNEXPECTED drops
# trigger a warning; warning(), not stop(), since killing the whole main.R run over one collinear
# coefficient in a robustness spec would be disproportionate -- matches this codebase's existing
# non-destructive convention (e.g. calibrate_isco_exposure() keeps a theoretical value rather than
# aborting).
check_for_dropped_coefficients <- function(model, model_name, expected_drops = character(0)) {
  dropped <- model$collin.var
  unexpected <- setdiff(dropped, expected_drops)
  if (length(unexpected) > 0) {
    warning(sprintf(
      "check_for_dropped_coefficients: %s had %d unexpected variable(s) dropped by collinearity: %s",
      model_name, length(unexpected), paste(unexpected, collapse = ", ")
    ))
  }
  invisible(dropped)
}
