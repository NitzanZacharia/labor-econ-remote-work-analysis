# ddd_exposure_family_wald_test.R
# Joint significance test on the family of WFH_Exposure interaction terms in the primary DDD
# (Mother:WFH_Exposure, Post:WFH_Exposure, Mother:Post:WFH_Exposure). Each is estimated
# imprecisely on its own -- Mother:Post:WFH_Exposure's own MDE is a large fraction of the baseline
# employment rate, per docs/decisions/exposure-cell-granularity-fix.md -- but the three terms share
# the same WFH_Exposure regressor and the same sample, so their sampling errors are correlated.
# A null single-coefficient result on the triple interaction alone does not establish that the
# whole exposure-interaction family carries no signal; fixest::wald() tests the joint null that all
# three are simultaneously zero, using the model's own cluster-robust vcov, which can have more
# power than any one of the three marginal tests.
library(fixest)

run_ddd_exposure_family_wald_test <- function(model) {
  w <- wald(model, keep = "^Mother:WFH_Exposure$|^Post:WFH_Exposure$|^Mother:Post:WFH_Exposure$")

  message(sprintf(
    paste0(
      "=== Joint Wald test, H0: {Mother:WFH_Exposure, Post:WFH_Exposure, ",
      "Mother:Post:WFH_Exposure} all = 0 ===\nF(%d, %.0f) = %.4f, p = %.4f (%s)"
    ),
    w$df1, w$df2, w$stat, w$p, w$vcov
  ))

  invisible(w)
}
