# basic_reg_own_occ_exposure.R
# Outside-the-box direction #4 (docs/decisions/extensive-margin-outside-the-box-directions.md):
# reframes "extensive margin" as occupational mobility rather than employment status -- did
# employed mothers sort into more/less WFH-exposed occupations post-2021, relative to employed
# non-mothers?
#
# Originally proposed as an individual-level pre/post occupation-exposure change, but
# docs/decisions/panel-fe-rejected.md already confirms that's not viable: only 1.88% of IDPUFs
# (1,514 individuals) straddle the Post boundary at all. Reformulated as a repeated-cross-section
# DiD instead: Employed==1 subsample, outcome is each respondent's OWN occupation's calibrated
# exposure score (wfh_exposure_calibrated from calibrate_isco_exposure(), joined by her actual
# MishlachYad_ISCO_08_2 -- NOT the demographic-cell shift-share WFH_Exposure used elsewhere, which
# is a property of her demographic cell, not her actual job).
library(tidyverse)
library(fixest)
source(file.path("scripts", "data_processing.R"))
source(file.path("scripts", "ddd_collinearity_diagnostics.R"))

basic_reg_own_occ_exposure <- function(cleaned_df, exposure_calibrated, controls = DEFAULT_CONTROLS) {
  df <- cleaned_df %>%
    filter(Employed == 1) %>%
    left_join(
      exposure_calibrated %>% select(ISCO2, OwnOccExposure = wfh_exposure_calibrated),
      by = c("MishlachYad_ISCO_08_2" = "ISCO2")
    )

  message(sprintf(
    "basic_reg_own_occ_exposure: %d of %d employed rows unmatched to a calibrated occupation score (OwnOccExposure NA).",
    sum(is.na(df$OwnOccExposure)), nrow(df)
  ))
  df <- filter(df, !is.na(OwnOccExposure))

  rhs <- paste("Mother + Post + Mother:Post +", paste(controls, collapse = " + "))
  formula_own_occ <- as.formula(paste("OwnOccExposure ~", rhs))

  reg <- feols(formula_own_occ, data = df, cluster = ~IDPUF)
  check_for_dropped_coefficients(reg, "basic_reg_own_occ_exposure()'s model")

  table_own_occ <- etable(reg, headers = c("OwnOccExposure"), digits = 4)
  print(table_own_occ)

  invisible(list(table = table_own_occ, model = reg))
}
