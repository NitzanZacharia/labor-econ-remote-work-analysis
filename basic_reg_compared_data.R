#basic_regression_compared_data
library(tidyverse)
library(fixest)
source("data_processing.R")

basic_reg_comp <- function(cleaned_data) {
  
  # ──  Define control variables ──────────────────────────────────────────────
  controls <- c(
    "MatzavMishpachti",
    "Dat",
    "GilNK",
    "MachozMegurim",
    "TeudaGvoha",
    "MisparHorimYechidim"
  )
  
  rhs <- paste(
    "Mother + Post + Mother:Post",
    paste(controls, collapse = " + "),
    sep = " + "
  )
  
  formula_employed <- as.formula(paste("Employed ~", rhs))
  
  # ──  Run on full sample (includes imputed Employed) ────────────────────────
  reg_employed <- feols(formula_employed, data = cleaned_data, cluster = ~IDPUF)
  
  # ──  Run on Muasak-observed only (robustness check) ───────────────────────
  reg_employed_muasak <- feols(formula_employed, 
                               data = filter(cleaned_data, !is.na(Muasak)), 
                               cluster = ~IDPUF)
  
  # ──  Display side-by-side ──────────────────────────────────────────────────
  table_basic <- etable(
    reg_employed,
    reg_employed_muasak,
    headers  = c("Full Sample (w/ Imputation)", "Muasak-Observed Only"),
    digits   = 4
  )
  print(table_basic)
  
  return(invisible(list(
    table  = table_basic,
    models = list(
      employed       = reg_employed,
      employed_muasak = reg_employed_muasak
    )
  )))
}