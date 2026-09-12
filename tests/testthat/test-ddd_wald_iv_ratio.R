# test-ddd_wald_iv_ratio.R
# Unit tests for compute_ddd_wald_iv_ratio() (scripts/ddd_wald_iv_ratio.R). The ratio/delta-method
# formulas are closed-form, so these tests fit small real fixest models, extract each one's own
# coefficient/SE, and check the function's output against the formula computed by hand -- same
# style as test-ddd_mde_diagnostics.R and test-ddd_exposure_synthesis.R.

make_rf_model <- function(seed) {
  set.seed(seed)
  n <- 500
  df <- data.frame(
    Mother = sample(0:1, n, replace = TRUE),
    Post   = sample(0:1, n, replace = TRUE),
    WFH_Exposure = runif(n)
  )
  df$Employed <- rnorm(n)
  fixest::feols(Employed ~ Mother * Post * WFH_Exposure, data = df)
}

make_fs_model <- function(seed) {
  set.seed(seed)
  n <- 500
  df <- data.frame(WFH_Exposure = runif(n))
  df$WFH_RefWeek <- 0.8 * df$WFH_Exposure + rnorm(n, sd = 0.3)
  fixest::feols(WFH_RefWeek ~ WFH_Exposure, data = df)
}

test_that("compute_ddd_wald_iv_ratio's ratio estimate/SE match the delta-method formula by hand", {
  rf_model <- make_rf_model(1)
  fs_model <- make_fs_model(2)

  rf_estimate <- unname(coef(rf_model)[["Mother:Post:WFH_Exposure"]])
  rf_se       <- unname(fixest::se(rf_model)[["Mother:Post:WFH_Exposure"]])
  fs_estimate <- unname(coef(fs_model)[["WFH_Exposure"]])
  fs_se       <- unname(fixest::se(fs_model)[["WFH_Exposure"]])

  expected_ratio <- rf_estimate / fs_estimate
  expected_se <- sqrt(rf_se^2 / fs_estimate^2 + (rf_estimate^2 * fs_se^2) / fs_estimate^4)
  expected_z <- expected_ratio / expected_se
  expected_p <- 2 * (1 - pnorm(abs(expected_z)))

  result <- suppressMessages(compute_ddd_wald_iv_ratio(rf_model, fs_model))

  expect_equal(result$ratio_estimate, expected_ratio, tolerance = 1e-8)
  expect_equal(result$ratio_se, expected_se, tolerance = 1e-8)
  expect_equal(result$z, expected_z, tolerance = 1e-8)
  expect_equal(result$p, expected_p, tolerance = 1e-8)
})

test_that("compute_ddd_wald_iv_ratio respects custom coefficient names", {
  set.seed(3)
  n <- 500
  df <- data.frame(x = rnorm(n), z = rnorm(n))
  df$y <- rnorm(n)
  rf_model <- fixest::feols(y ~ x, data = df)
  fs_model <- fixest::feols(y ~ z, data = df)

  result <- suppressMessages(compute_ddd_wald_iv_ratio(
    rf_model, fs_model, rf_coef_name = "x", fs_coef_name = "z"
  ))
  expected_ratio <- unname(coef(rf_model)[["x"]]) / unname(coef(fs_model)[["z"]])
  expect_equal(result$ratio_estimate, expected_ratio, tolerance = 1e-8)
})

test_that("compute_ddd_wald_iv_ratio errors clearly when the reduced-form coefficient is missing", {
  rf_model <- make_rf_model(4)
  fs_model <- make_fs_model(5)
  expect_error(
    compute_ddd_wald_iv_ratio(rf_model, fs_model, rf_coef_name = "not_a_real_coef"),
    "not found"
  )
})

test_that("compute_ddd_wald_iv_ratio errors clearly when the first-stage coefficient is missing", {
  rf_model <- make_rf_model(6)
  fs_model <- make_fs_model(7)
  expect_error(
    compute_ddd_wald_iv_ratio(rf_model, fs_model, fs_coef_name = "not_a_real_coef"),
    "not found"
  )
})

test_that("compute_ddd_wald_iv_ratio guards against division by an exactly-zero first-stage coefficient", {
  set.seed(8)
  rf_model <- fixest::feols(y ~ x, data = { d <- data.frame(x = rnorm(200)); d$y <- rnorm(200); d })

  # Exactly-orthogonal paired design: for each pair, z = -1 then +1, with an IDENTICAL w in both
  # rows. This forces the OLS slope on z to be mathematically exactly 0 (every pair contributes
  # (-1)*(w-mean) + (1)*(w-mean) = 0 to the covariance), while w still varies across pairs, so
  # residual variance -- and therefore z's SE -- stays finite and well-defined (not NaN/degenerate).
  n_pairs <- 100
  w_pairs <- rnorm(n_pairs)
  df_orth <- data.frame(z = rep(c(-1, 1), times = n_pairs), w = rep(w_pairs, each = 2))
  fs_model <- fixest::feols(w ~ z, data = df_orth)
  expect_equal(unname(coef(fs_model)[["z"]]), 0, tolerance = 1e-10)  # sanity check on the construction

  expect_error(
    compute_ddd_wald_iv_ratio(rf_model, fs_model, rf_coef_name = "x", fs_coef_name = "z"),
    "undefined"
  )
})

test_that("compute_ddd_wald_iv_ratio's message includes the rescaling interpretation", {
  rf_model <- make_rf_model(9)
  fs_model <- make_fs_model(10)
  expect_message(
    compute_ddd_wald_iv_ratio(rf_model, fs_model),
    "Implied effect on employment probability"
  )
})
