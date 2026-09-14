# basic_reg_combined_hours_margin.R
# Outside-the-box direction #3 (docs/decisions/extensive-margin-outside-the-box-directions.md):
# tests whether mothers substitute toward fewer hours WITHIN employment rather than leaving
# employment, by building a combined "hours including zeros" outcome (WorkHoursCont for employed
# women, 0 for non-employed) and running the exact same Mother*Post DiD basic_reg()/
# intensive_margin_regression.R already use, on the full sample instead of the Employed==1
# subsample. A dependency-free stand-in for a Tobit/hurdle model (no censored-regression package is
# in this project -- CLAUDE.md requires flagging a new one before adding it, and this avoids
# needing one): if the null extensive-margin result and the significant intensive-margin result
# reflect the SAME underlying substitution (mothers stay employed but cut hours), the combined
# outcome should track the intensive-margin signal rather than sit at the extensive-margin's flat
# zero. WorkHoursCont is deliberately NA (not 0) for non-employed rows in data_processing.R ("usual
# weekly hours" undefined without a job) -- the zero-fill here is a new variable, not a
# reinterpretation of the existing one, and preserves NA for rows where Employed itself is NA.
library(tidyverse)
library(fixest)
source(file.path("scripts", "data_processing.R"))
source(file.path("scripts", "ddd_collinearity_diagnostics.R"))

basic_reg_combined_hours_margin <- function(cleaned_df, controls = DEFAULT_CONTROLS) {
  df <- cleaned_df %>%
    mutate(HoursIncludingZero = case_when(
      is.na(Employed) ~ NA_real_,
      Employed == 1   ~ WorkHoursCont,
      Employed == 0   ~ 0
    ))

  rhs <- paste("Mother + Post + Mother:Post +", paste(controls, collapse = " + "))
  formula_hours0 <- as.formula(paste("HoursIncludingZero ~", rhs))

  reg <- feols(formula_hours0, data = df, cluster = ~IDPUF)
  check_for_dropped_coefficients(reg, "basic_reg_combined_hours_margin()'s model")

  table_hours0 <- etable(reg, headers = c("HoursIncludingZero"), digits = 4)
  print(table_hours0)

  invisible(list(table = table_hours0, model = reg))
}
