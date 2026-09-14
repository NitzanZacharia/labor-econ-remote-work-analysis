# basic_reg_jewish_arab_equality.R
# Formal test of whether Mother:Post differs between Jewish and Arab women -- generalizes
# basic_reg() (main.R lines 83-87 fit two SEPARATE basic_reg() calls on filter(Leom==1) and
# filter(Leom==2), never formally compared). Non-overlapping/overlapping confidence intervals
# across two independent models is not itself a test of whether the two point estimates differ
# from each other; a single pooled regression with a Mother:Post:LeomGroup interaction is.
#
# Leom is documented as a raw, unconverted passthrough (docs/LLD.md row 38, "used as a filter
# value, not a regression factor") -- restricted here to Leom %in% c(1, 2) to match exactly the
# same two subsamples the existing separate regressions already cover, not a broader population.
library(tidyverse)
library(fixest)
source(file.path("scripts", "data_processing.R"))
source(file.path("scripts", "ddd_collinearity_diagnostics.R"))

basic_reg_jewish_arab_equality <- function(cleaned_df) {
  controls <- DEFAULT_CONTROLS

  df <- cleaned_df %>%
    filter(Leom %in% c(1, 2)) %>%
    mutate(LeomGroup = factor(if_else(Leom == 1, "Jewish", "Arab"), levels = c("Jewish", "Arab")))

  n_by_group <- count(df, LeomGroup)
  print(n_by_group)

  rhs <- paste("Mother * Post * LeomGroup +", paste(controls, collapse = " + "))
  formula_employed <- as.formula(paste("Employed ~", rhs))

  reg <- feols(formula_employed, data = df, cluster = ~IDPUF)
  check_for_dropped_coefficients(reg, "basic_reg_jewish_arab_equality()'s model")

  table_equality <- etable(reg, headers = c("Employed"), digits = 4)
  print(table_equality)

  invisible(list(table = table_equality, model = reg, n_by_group = n_by_group))
}
