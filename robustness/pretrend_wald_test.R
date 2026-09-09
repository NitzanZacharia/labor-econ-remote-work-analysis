# pretrend_wald_test.R
# Phase 1c: joint significance test on the pre-2020 Mother:year interaction coefficients already
# estimated by Diagnostics.R's event-study regression (run_diagnostics()'s pretrend_model,
# i(ShnatSeker, Mother, ref=2019)). Diagnostics.R itself only reports each coefficient
# individually (etable()); parallel trends requires them to be jointly, not just individually,
# indistinguishable from zero, which is what this adds via fixest's own wald().
#
# Pre-2020 here means ShnatSeker %in% c(2017, 2018) -- 2019 is the omitted reference year and 2020
# itself is excluded from this project's sample entirely, so those are the only two pre-period
# interaction terms fixest's i() produces. Confirmed against a scratch fixest model that
# i(ShnatSeker, Mother, ref=2019) names them "ShnatSeker::2017:Mother" and
# "ShnatSeker::2018:Mother" (not "Mother:ShnatSeker::...").
library(fixest)

run_pretrend_joint_test <- function(pretrend_model) {
  w <- wald(pretrend_model, keep = "ShnatSeker::(2017|2018):Mother")

  message(sprintf(
    "=== Joint Wald test, H0: pre-2020 Mother:year coefficients = 0 ===\nF(%d, %.0f) = %.4f, p = %.4f (%s)",
    w$df1, w$df2, w$stat, w$p, w$vcov
  ))

  invisible(w)
}
