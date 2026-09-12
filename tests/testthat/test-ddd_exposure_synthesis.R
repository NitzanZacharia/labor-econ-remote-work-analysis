# test-ddd_exposure_synthesis.R
# Unit tests for synthesize_ddd_triple_interaction() (scripts/ddd_exposure_synthesis.R). The
# pooling/heterogeneity formulas are closed-form (inverse-variance weighting, Cochran's Q), so
# these tests fit small real fixest models, extract each one's own coefficient/SE, and check the
# function's output against the formula computed by hand -- same style as test-ddd_mde_diagnostics.R.

make_coef_model <- function(coef_name, seed) {
  set.seed(seed)
  n <- 500
  df <- data.frame(x = rnorm(n))
  names(df) <- coef_name
  df$y <- rnorm(n)
  fixest::feols(as.formula(paste("y ~", coef_name)), data = df)
}

test_that("synthesize_ddd_triple_interaction's pooled estimate/SE match the inverse-variance formula by hand", {
  models <- list(
    a = make_coef_model("x", seed = 1),
    b = make_coef_model("x", seed = 2),
    c = make_coef_model("x", seed = 3)
  )
  estimate <- vapply(models, function(m) unname(coef(m)[["x"]]), numeric(1))
  se       <- vapply(models, function(m) unname(fixest::se(m)[["x"]]), numeric(1))
  w        <- 1 / se^2
  expected_pooled_estimate <- sum(w * estimate) / sum(w)
  expected_pooled_se       <- sqrt(1 / sum(w))

  result <- synthesize_ddd_triple_interaction(models, coef_name = "x")

  expect_equal(result$pooled_estimate, expected_pooled_estimate, tolerance = 1e-8)
  expect_equal(result$pooled_se, expected_pooled_se, tolerance = 1e-8)
  expect_equal(nrow(result$per_model), 3)
})

test_that("synthesize_ddd_triple_interaction's Cochran's Q matches the formula by hand", {
  models <- list(
    a = make_coef_model("x", seed = 10),
    b = make_coef_model("x", seed = 20)
  )
  estimate <- vapply(models, function(m) unname(coef(m)[["x"]]), numeric(1))
  se       <- vapply(models, function(m) unname(fixest::se(m)[["x"]]), numeric(1))
  w        <- 1 / se^2
  pooled   <- sum(w * estimate) / sum(w)
  expected_q <- sum(w * (estimate - pooled)^2)

  result <- synthesize_ddd_triple_interaction(models, coef_name = "x")

  expect_equal(result$q_stat, expected_q, tolerance = 1e-8)
  expect_equal(result$q_df, 1)
  expect_true(result$q_p >= 0 && result$q_p <= 1)
})

test_that("synthesize_ddd_triple_interaction flags heterogeneous = TRUE when two precise estimates strongly disagree", {
  set.seed(42)
  n <- 20000
  df1 <- data.frame(x = rnorm(n)); df1$y <-  2 * df1$x + rnorm(n, sd = 0.1)
  df2 <- data.frame(x = rnorm(n)); df2$y <- -2 * df2$x + rnorm(n, sd = 0.1)
  models <- list(
    pos = fixest::feols(y ~ x, data = df1),
    neg = fixest::feols(y ~ x, data = df2)
  )

  result <- synthesize_ddd_triple_interaction(models, coef_name = "x")
  expect_true(result$heterogeneous)
  expect_true(result$q_p < 0.05)
})

test_that("synthesize_ddd_triple_interaction identifies the most precise model correctly", {
  models <- list(
    imprecise = make_coef_model("x", seed = 100),
    precise   = fixest::feols(y ~ x, data = {
      set.seed(101); d <- data.frame(x = rnorm(5000)); d$y <- 0.5 * d$x + rnorm(5000); d
    })
  )
  result <- synthesize_ddd_triple_interaction(models, coef_name = "x")
  expect_equal(result$most_precise_model, "precise")
})

test_that("synthesize_ddd_triple_interaction errors clearly when the coefficient is missing from a model", {
  models <- list(
    a = make_coef_model("x", seed = 1),
    b = fixest::feols(y ~ z, data = { set.seed(2); d <- data.frame(z = rnorm(200)); d$y <- rnorm(200); d })
  )
  expect_error(synthesize_ddd_triple_interaction(models, coef_name = "x"), "not found")
})

test_that("synthesize_ddd_triple_interaction requires named models", {
  models <- list(make_coef_model("x", seed = 1), make_coef_model("x", seed = 2))
  expect_error(synthesize_ddd_triple_interaction(models, coef_name = "x"))
})
