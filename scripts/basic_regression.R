#basic_regression
library(tidyverse)
library(fixest)
source(file.path("scripts", "data_processing.R"))
source(file.path("scripts", "ddd_collinearity_diagnostics.R"))

basic_reg <- function(cleaned_data) {
  
  
  
  # ──  Define control variables ──────────────────────────────────────────────
  controls <- DEFAULT_CONTROLS

  # ──  Build formula ─────────────────────────────────────────────────────────
  rhs <- paste(
    "Mother + Post + Mother:Post",
    paste(controls, collapse = " + "),
    sep = " + "
  )
  
  formula_employed <- as.formula(paste("Employed ~", rhs))
  
  # ──  Run regression ───────────────────────────────────────────────────────
  reg_employed <- feols(formula_employed, data = cleaned_data, cluster = ~IDPUF)
  check_for_dropped_coefficients(reg_employed, "basic_reg()'s Employed model")

  # ──  Display and return results ─────────────────────────────────────────────
  table_basic <- etable(reg_employed, 
                        headers = c("Employed"),
                        digits = 4)
  print(table_basic)
  return(invisible(list(
    table   = table_basic,
    models  = list(employed = reg_employed)
  )))
}


