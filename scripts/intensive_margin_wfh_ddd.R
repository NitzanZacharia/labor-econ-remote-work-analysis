# intensive_margin_wfh_ddd.R
# WFH-mechanism triple interaction on the INTENSIVE margin (hours), not the extensive margin
# (Employed) every other DDD spec in this pipeline uses. Employed is a 0/1 indicator, structurally
# blind to an intensification channel: a mother in a high-WFH-exposure occupation already employed
# pre-2021 who moves from part-time to full-time post-2021 (e.g. a commute/schedule constraint
# removed by WFH) produces zero movement in Employed and is invisible to every spec run so far. This
# is a genuinely different outcome margin, not a rehash of the occupation-level-exposure critique
# (which concerned regressor construction, not the outcome) or the panel-FE rejection (this stays
# repeated-cross-section, per docs/decisions/panel-fe-rejected.md).
#
# Mirrors intensive_margin_regression.R's Employed==1 subsample restriction (hours are only
# meaningful conditional on being employed) and main.R's exact primary-DDD Spec 1/Spec 2 formula
# structure (Mother * Post * WFH_Exposure + Mother:GilNK + controls, cell-clustered), swapping only
# the outcome from Employed to WorkHoursCont.
#
# CAVEAT (state alongside any result from this function, don't just report the point estimate):
# conditioning hours on Employed==1 has the same selection-on-a-mediator problem
# intensive_margin_lee_bounds.R was built to address for the plain Mother:Post case -- a significant
# WFH-exposure triple interaction here is suggestive of an intensification channel, not final,
# pending a Lee-bounds extension with a WFH_Exposure interaction (build that follow-up only if this
# shows signal).
library(tidyverse)
library(fixest)
source(file.path("scripts", "data_processing.R"))

run_intensive_margin_wfh_ddd <- function(cleaned_df, exposure_cells, controls = DEFAULT_CONTROLS,
                                          cell_fe_vars = c("GilNK", "TeudaGvoha", "MachozMegurim")) {
  other_controls  <- setdiff(controls, cell_fe_vars)
  cluster_formula <- as.formula(paste("~", paste(cell_fe_vars, collapse = "^")))

  exposure_join_vars <- setdiff(names(exposure_cells), c("WFH_Exposure", "n_cell"))
  ddd_df <- cleaned_df %>%
    filter(Employed == 1) %>%
    left_join(exposure_cells, by = exposure_join_vars) %>%
    filter(!is.na(WFH_Exposure))

  message(sprintf(
    "run_intensive_margin_wfh_ddd: %d Employed==1 rows with a matched exposure cell.", nrow(ddd_df)
  ))

  additive <- feols(
    as.formula(paste("WorkHoursCont ~ Mother * Post * WFH_Exposure + Mother:GilNK +",
                      paste(controls, collapse = " + "))),
    data = ddd_df, cluster = cluster_formula
  )
  fe <- feols(
    as.formula(paste("WorkHoursCont ~ Mother * Post * WFH_Exposure + Mother:GilNK +",
                      paste(other_controls, collapse = " + "),
                      "|", paste(cell_fe_vars, collapse = "^"))),
    data = ddd_df, cluster = cluster_formula
  )
  check_for_dropped_coefficients(additive, "intensive-margin WFH DDD Spec 1 (additive)")
  check_for_dropped_coefficients(fe, "intensive-margin WFH DDD Spec 2 (cell FE)")

  intensive_wfh_ddd_table <- etable(
    additive, fe,
    headers = c("Hours DDD: additive", "Hours DDD: cell FE"), digits = 4
  )
  print(intensive_wfh_ddd_table)

  invisible(list(additive = additive, fe = fe, table = intensive_wfh_ddd_table, n = nrow(ddd_df)))
}
