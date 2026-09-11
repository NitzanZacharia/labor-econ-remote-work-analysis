# wfh_first_stage_check.R
# First-stage relevance check for the primary DDD's shift-share regressor: does WFH_Exposure (the
# pre-period, 2017-2019, demographic-cell exposure measure built by build_exposure_cells()) actually
# predict REALIZED work-from-home behavior once that becomes measurable? docs/decisions/
# calibrated-exposure-and-cell-ddd.md asserts this causal link but never tests it directly against
# real WFH/WFH_RefWeek data -- this function closes that gap.
#
# WFH/WFH_RefWeek are 100% NA for every ShnatSeker < 2021 row by CBS survey design (see
# data_processing.R's WFH block comment: the columns exist in the schema but weren't asked
# pre-2021). A differenced pre/post first stage is therefore not estimable -- any feols() with
# WFH_RefWeek as the outcome and Post as a regressor would listwise-drop every Post==0 row, leaving
# Post exactly collinear with the intercept. So both checks below are restricted to Post == 1,
# where WFH_RefWeek is actually observed, and ask a within-post-period question instead:
#   (1) is WFH_Exposure a significant, positive predictor of realized WFH_RefWeek at all, and
#   (2) does that relationship strengthen over 2021-2023 (the closest available analog to
#       "high-exposure cells pick up more WFH after treatment" given there's no pre-2021 realized-
#       WFH baseline to difference against).
library(tidyverse)
library(fixest)

check_wfh_first_stage_relevance <- function(ddd_df, controls = DEFAULT_CONTROLS) {
  cell_fe_vars   <- c("GilNK", "TeudaGvoha", "MachozMegurim")
  other_controls <- setdiff(controls, cell_fe_vars)
  cell_cluster_formula <- as.formula(paste("~", paste(cell_fe_vars, collapse = "^")))

  post_df <- ddd_df %>% filter(Post == 1)

  message("Checking WFH_Exposure's first-stage relevance against realized WFH_RefWeek (Post==1 only)...")

  level_reg <- feols(
    as.formula(paste("WFH_RefWeek ~ WFH_Exposure +", paste(other_controls, collapse = " + "))),
    data = post_df, cluster = cell_cluster_formula
  )

  # i(ShnatSeker, WFH_Exposure, ref = 2021) mirrors Diagnostics.R's i(ShnatSeker, Mother, ref=2019)
  # idiom: one interaction coefficient per non-reference year, testing whether the WFH_Exposure ->
  # WFH_RefWeek slope grows relative to 2021 (the first year WFH_RefWeek is observed at all).
  dynamic_reg <- feols(
    as.formula(paste(
      "WFH_RefWeek ~ WFH_Exposure + i(ShnatSeker, WFH_Exposure, ref = 2021) +",
      paste(other_controls, collapse = " + ")
    )),
    data = post_df, cluster = cell_cluster_formula
  )

  check_for_dropped_coefficients(level_reg, "WFH first-stage relevance (level)")
  check_for_dropped_coefficients(dynamic_reg, "WFH first-stage relevance (dynamic)")

  first_stage_table <- etable(
    level_reg, dynamic_reg,
    headers = c("Level: WFH_Exposure -> WFH_RefWeek", "Dynamic: WFH_Exposure x Year"),
    digits = 4
  )
  print(first_stage_table)

  invisible(list(
    level_reg   = level_reg,
    dynamic_reg = dynamic_reg,
    table       = first_stage_table
  ))
}
