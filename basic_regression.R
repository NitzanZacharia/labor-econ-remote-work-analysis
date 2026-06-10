#basic_regression
library(tidyverse)
library(fixest)
source("data_processing.R")

basic_reg <- function(cleaned_data) {
  
  
  
  # ──  Define control variables ──────────────────────────────────────────────
  controls <- c(
    "MatzavMishpachti",       # marital status
    "Dat",                    # religiosity
    "GilNK",                  # age group
    "MachozMegurim",          # district of residence
    "TeudaGvoha",             # education
    "MisparHorimYechidim"     # single parent indicator
  )
  
  # ──  Build formula ─────────────────────────────────────────────────────────
  rhs <- paste(
    "Mother + Post + Mother:Post",
    paste(controls, collapse = " + "),
    sep = " + "
  )
  
  formula_employed <- as.formula(paste("Employed ~", rhs))
  
  # ──  Run regression ───────────────────────────────────────────────────────
  reg_employed <- feols(formula_employed, data = cleaned_data, cluster = ~IDPUF)
  
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


