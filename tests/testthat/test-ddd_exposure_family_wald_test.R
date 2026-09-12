# test-ddd_exposure_family_wald_test.R
# Unit tests for run_ddd_exposure_family_wald_test() (scripts/ddd_exposure_family_wald_test.R),
# against small synthetic fixest models fit directly with Mother*Post*WFH_Exposure -- the exact
# specification the primary DDD uses -- rather than depending on main.R's real data pipeline.

make_ddd_model <- function(extra_rhs = NULL, seed = 1) {
  set.seed(seed)
  n <- 3000
  df <- data.frame(
    Mother       = sample(0:1, n, replace = TRUE),
    Post         = sample(0:1, n, replace = TRUE),
    WFH_Exposure = runif(n),
    Z            = rnorm(n),
    IDPUF        = sample(1:300, n, replace = TRUE)
  )
  df$Employed <- rbinom(n, 1, 0.5)
  rhs <- "Mother*Post*WFH_Exposure"
  if (!is.null(extra_rhs)) rhs <- paste(rhs, "+", extra_rhs)
  fixest::feols(as.formula(paste("Employed ~", rhs)), data = df, cluster = ~IDPUF)
}

test_that("run_ddd_exposure_family_wald_test restricts the joint test to exactly the 3 interaction terms", {
  m <- make_ddd_model()
  w <- suppressMessages(run_ddd_exposure_family_wald_test(m))

  expect_true(all(c("stat", "p", "df1", "df2", "vcov") %in% names(w)))
  expect_equal(w$df1, 3)  # Mother:WFH_Exposure, Post:WFH_Exposure, Mother:Post:WFH_Exposure
  expect_true(w$p >= 0 && w$p <= 1)
})

test_that("run_ddd_exposure_family_wald_test does not pick up the bare main effects or unrelated controls", {
  m <- make_ddd_model(extra_rhs = "Z")
  coefs <- names(coef(m))
  expect_true(all(c("Mother", "Post", "WFH_Exposure", "Z") %in% coefs))

  w <- suppressMessages(run_ddd_exposure_family_wald_test(m))
  expect_equal(w$df1, 3)  # still exactly 3 -- Z and the bare main effects excluded
})

test_that("run_ddd_exposure_family_wald_test's F-stat matches fixest::wald() called directly with the same restriction", {
  m <- make_ddd_model(seed = 7)
  expected <- fixest::wald(
    m, keep = "^Mother:WFH_Exposure$|^Post:WFH_Exposure$|^Mother:Post:WFH_Exposure$"
  )
  w <- suppressMessages(run_ddd_exposure_family_wald_test(m))

  expect_equal(w$stat, expected$stat, tolerance = 1e-8)
  expect_equal(w$p, expected$p, tolerance = 1e-8)
})
