# test-pretrend_wald_test.R
# Unit tests for run_pretrend_joint_test() (Phase 1c), against a small synthetic fixest model
# fit directly with i(ShnatSeker, ref=2019) + i(ShnatSeker, Mother, ref=2019) -- the exact
# specification run_diagnostics() uses -- rather than depending on run_diagnostics() itself or the
# project's fixture CSVs.

make_pretrend_model <- function() {
  set.seed(3)
  n <- 2000
  df <- data.frame(
    ShnatSeker = sample(c(2017, 2018, 2019, 2021, 2022, 2023), n, replace = TRUE),
    Mother     = sample(0:1, n, replace = TRUE),
    Employed   = sample(0:1, n, replace = TRUE),
    IDPUF      = sample(1:500, n, replace = TRUE)
  )
  fixest::feols(
    Employed ~ Mother + i(ShnatSeker, ref = 2019) + i(ShnatSeker, Mother, ref = 2019),
    data = df, cluster = ~IDPUF
  )
}

test_that("run_pretrend_joint_test returns a Wald test restricted to exactly the 2 pre-2020 terms", {
  m <- make_pretrend_model()
  w <- suppressMessages(run_pretrend_joint_test(m))

  expect_true(all(c("stat", "p", "df1", "df2", "vcov") %in% names(w)))
  expect_equal(w$df1, 2)  # exactly ShnatSeker::2017:Mother and ShnatSeker::2018:Mother
  expect_true(w$p >= 0 && w$p <= 1)
})

test_that("run_pretrend_joint_test's keep pattern does not pick up post-2020 Mother:year terms", {
  m <- make_pretrend_model()
  coefs <- names(coef(m))
  post_period_terms <- grep("ShnatSeker::(2021|2022|2023):Mother", coefs, value = TRUE)
  expect_true(length(post_period_terms) == 3)  # sanity: these terms do exist in the model

  w <- suppressMessages(run_pretrend_joint_test(m))
  expect_equal(w$df1, 2)  # confirms none of the 3 post-period terms leaked into the joint test
})
