# test-ddd_mde_diagnostics.R
# Unit tests for compute_ddd_mde() (scripts/ddd_mde_diagnostics.R). The MDE formula is closed-form
# (SE * (qnorm(1 - sig_level/2) + qnorm(power))), so these tests fit small real fixest models and
# check the function's output against the formula computed by hand from the same model's own SE --
# no data fixture pipeline needed.

test_that("compute_ddd_mde matches the closed-form formula computed by hand from the model's own SE", {
  set.seed(1)
  df <- data.frame(y = rnorm(200), x = rnorm(200))
  m  <- fixest::feols(y ~ x, data = df)

  se_x          <- unname(fixest::se(m)["x"])
  expected_mde  <- se_x * (qnorm(0.975) + qnorm(0.8))

  result <- compute_ddd_mde(m, coef_name = "x")

  expect_equal(result$mde, expected_mde, tolerance = 1e-8)
  expect_equal(result$se, se_x, tolerance = 1e-8)
  expect_equal(result$point_estimate, unname(coef(m)["x"]), tolerance = 1e-8)
})

test_that("compute_ddd_mde respects custom sig_level/power", {
  set.seed(2)
  df <- data.frame(y = rnorm(200), x = rnorm(200))
  m  <- fixest::feols(y ~ x, data = df)

  se_x         <- unname(fixest::se(m)["x"])
  expected_mde <- se_x * (qnorm(1 - 0.1 / 2) + qnorm(0.9))

  result <- compute_ddd_mde(m, coef_name = "x", sig_level = 0.1, power = 0.9)
  expect_equal(result$mde, expected_mde, tolerance = 1e-8)
})

test_that("compute_ddd_mde errors clearly when the named coefficient was dropped by collinearity", {
  set.seed(3)
  df <- data.frame(y = rnorm(50), x1 = rnorm(50))
  df$x2 <- df$x1  # exactly collinear with x1 -> dropped by feols()
  m <- suppressWarnings(fixest::feols(y ~ x1 + x2, data = df))

  expect_error(compute_ddd_mde(m, coef_name = "x2"), "not found")
})

test_that("compute_ddd_mde errors on a coefficient name absent from the model entirely", {
  df <- data.frame(y = rnorm(50), x1 = rnorm(50))
  m  <- fixest::feols(y ~ x1, data = df)

  expect_error(compute_ddd_mde(m, coef_name = "not_a_real_coef"), "not found")
})

test_that("within_mde correctly flags a point estimate smaller than the MDE", {
  set.seed(4)
  # A tiny, noisy true relationship: the point estimate should land well inside the MDE.
  df <- data.frame(x = rnorm(500))
  df$y <- 0.0001 * df$x + rnorm(500)
  m <- fixest::feols(y ~ x, data = df)

  result <- compute_ddd_mde(m, coef_name = "x")
  expect_true(is.logical(result$within_mde))
  expect_equal(result$within_mde, abs(result$point_estimate) < result$mde)
})

test_that("compute_ddd_mde's message includes the baseline-rate framing when baseline_rate is supplied", {
  df <- data.frame(y = rnorm(200), x = rnorm(200))
  m  <- fixest::feols(y ~ x, data = df)

  expect_message(
    compute_ddd_mde(m, coef_name = "x", baseline_rate = 0.75),
    "baseline employment rate"
  )
})
