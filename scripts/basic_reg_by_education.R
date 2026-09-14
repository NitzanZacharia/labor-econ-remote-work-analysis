# basic_reg_by_education.R
# Outside-the-box direction #1 (docs/decisions/extensive-margin-outside-the-box-directions.md):
# TeudaGvoha (education) currently enters the primary DDD only as an additive DEFAULT_CONTROLS
# term. That's the exact same blind spot GilNK had before Mother:GilNK was added and revealed a
# masked age-increasing motherhood penalty (docs/decisions/age-balance-robustness-chain.md).
# Education plausibly gates WFH access and job security the same way age does, so this tests
# Mother*TeudaGvoha*Post directly -- reduced-form (no WFH_Exposure), same convention as
# basic_reg_by_child_age.R.
library(tidyverse)
library(fixest)
source(file.path("scripts", "data_processing.R"))
source(file.path("scripts", "ddd_collinearity_diagnostics.R"))

basic_reg_by_education <- function(cleaned_df) {
  controls <- setdiff(DEFAULT_CONTROLS, "TeudaGvoha")

  n_by_group <- count(cleaned_df, Mother, TeudaGvoha)
  print(n_by_group)

  rhs <- paste("Mother * TeudaGvoha * Post +", paste(controls, collapse = " + "))
  formula_employed <- as.formula(paste("Employed ~", rhs))

  reg <- feols(formula_employed, data = cleaned_df, cluster = ~IDPUF)
  check_for_dropped_coefficients(reg, "basic_reg_by_education()'s model")

  joint_test <- wald(reg, keep = "^Mother:TeudaGvoha.*:Post$")

  table_education <- etable(reg, headers = c("Employed"), digits = 4)
  print(table_education)
  message(sprintf(
    "=== Joint Wald test, H0: the Mother:TeudaGvoha:Post terms are jointly zero ===\nF(%d, %.0f) = %.4f, p = %.4f",
    joint_test$df1, joint_test$df2, joint_test$stat, joint_test$p
  ))

  invisible(list(table = table_education, model = reg, joint_test = joint_test, n_by_group = n_by_group))
}
