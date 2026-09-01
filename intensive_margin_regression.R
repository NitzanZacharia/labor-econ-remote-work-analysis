#intensive_margin_regression
# Checkpoint 4 (docs/ROADMAP.md): the intensive-margin counterpart to basic_regression.R's
# extensive-margin (Employed) model, per the research doc's core DiD spec (Part 2 §1 / Part 4 §2),
# which models both an employment indicator and weekly work hours. Hours are only meaningful
# conditional on being employed, so this is estimated on the Employed == 1 subsample.
library(tidyverse)
library(fixest)
source("data_processing.R")

run_intensive_margin_reg <- function(cleaned_df, controls = DEFAULT_CONTROLS) {

  # ──  Build formula ─────────────────────────────────────────────────────────
  rhs <- paste(
    "Mother + Post + Mother:Post",
    paste(controls, collapse = " + "),
    sep = " + "
  )

  formula_hours <- as.formula(paste("WorkHoursCont ~", rhs))

  # ──  Run regression (conditional on employment) ────────────────────────────
  reg_hours <- feols(formula_hours, data = filter(cleaned_df, Employed == 1), cluster = ~IDPUF)

  # ──  Display and return results ─────────────────────────────────────────────
  table_hours <- etable(reg_hours,
                         headers = c("WorkHoursCont"),
                         digits = 4)
  print(table_hours)
  return(invisible(list(
    table  = table_hours,
    models = list(hours = reg_hours)
  )))
}
