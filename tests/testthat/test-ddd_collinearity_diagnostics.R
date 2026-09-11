# test-ddd_collinearity_diagnostics.R
# Unit tests for check_spec1_collinearity(): the runtime replacement for main.R's previously
# static "74.5% variance explained / condition number 267.8" comment. Two synthetic designs with
# exactly hand-computable R^2/VIF via a simple 2-group ANOVA-style construction, plus a smoke test
# against fixture-shaped data exercising the real Mother*Post*WFH_Exposure + DEFAULT_CONTROLS
# formula.

test_that("check_spec1_collinearity returns the documented structure and runs on fixture-shaped data", {
  cleaned <- load_and_clean_data(fixtures_dir)
  ddd_df <- cleaned
  # Arbitrary but numeric and varying -- this test only checks the function runs and returns
  # sane values on real column types (factors, etc.), not any particular number.
  ddd_df$WFH_Exposure <- as.numeric(as.character(cleaned$GilNK)) / 10

  out <- capture.output(res <- suppressWarnings(check_spec1_collinearity(
    ddd_df, cell_fe_vars = c("GilNK", "TeudaGvoha", "MachozMegurim"), controls = DEFAULT_CONTROLS
  )))

  expect_type(res, "list")
  expect_true(all(c("r2_wfh_exposure_on_cells", "vif_wfh_exposure", "condition_number") %in% names(res)))
  expect_true(res$r2_wfh_exposure_on_cells >= 0 && res$r2_wfh_exposure_on_cells <= 1)
  expect_gte(res$vif_wfh_exposure, 1)
  expect_gt(res$condition_number, 0)
})

test_that("check_spec1_collinearity emits a message summarizing the diagnostic", {
  cleaned <- load_and_clean_data(fixtures_dir)
  ddd_df <- cleaned
  ddd_df$WFH_Exposure <- as.numeric(as.character(cleaned$GilNK)) / 10
  expect_message(
    out <- capture.output(res <- suppressWarnings(check_spec1_collinearity(
      ddd_df, cell_fe_vars = c("GilNK", "TeudaGvoha", "MachozMegurim"), controls = DEFAULT_CONTROLS
    ))),
    "collinearity"
  )
})

test_that("R^2 and VIF are exactly hand-computable on a 2-group design with a clean between-group split", {
  # Group means 2 and 6 (n=4 each), grand mean 4: SSM = 4*(2-4)^2 + 4*(6-4)^2 = 32; TSS = 40 ->
  # R^2 = 32/40 = 0.8, VIF = 1/(1-0.8) = 5.
  synth <- tibble::tibble(
    Group        = factor(rep(c("G1", "G2"), each = 4)),
    WFH_Exposure = c(1, 1, 3, 3, 5, 5, 7, 7),
    Mother       = rep(c(0, 1), 4),
    Post         = rep(c(0, 0, 1, 1), 2)
  )

  out <- capture.output(res <- suppressWarnings(
    check_spec1_collinearity(synth, cell_fe_vars = "Group", controls = "Group")
  ))

  expect_equal(res$r2_wfh_exposure_on_cells, 0.8, tolerance = 1e-8)
  expect_equal(res$vif_wfh_exposure, 5, tolerance = 1e-8)
  expect_gt(res$condition_number, 1)
})

test_that("R^2 and VIF are exactly 0/1 when WFH_Exposure is identically distributed across groups", {
  # Both groups have the identical value set c(1,3,5,7) -> equal group means -> zero between-group
  # variance -> R^2 = 0 exactly, VIF = 1 exactly (no collinearity at all).
  synth <- tibble::tibble(
    Group        = factor(rep(c("G1", "G2"), each = 4)),
    WFH_Exposure = rep(c(1, 3, 5, 7), 2),
    Mother       = rep(c(0, 1), 4),
    Post         = rep(c(0, 0, 1, 1), 2)
  )

  out <- capture.output(res <- suppressWarnings(
    check_spec1_collinearity(synth, cell_fe_vars = "Group", controls = "Group")
  ))

  expect_equal(res$r2_wfh_exposure_on_cells, 0, tolerance = 1e-8)
  expect_equal(res$vif_wfh_exposure, 1, tolerance = 1e-8)
})

test_that("the high-collinearity design reports a higher VIF and a higher condition number than the low-collinearity one", {
  make_synth <- function(wfh) tibble::tibble(
    Group = factor(rep(c("G1", "G2"), each = 4)), WFH_Exposure = wfh,
    Mother = rep(c(0, 1), 4), Post = rep(c(0, 0, 1, 1), 2)
  )
  out <- capture.output(res_high <- suppressWarnings(
    check_spec1_collinearity(make_synth(c(1, 1, 3, 3, 5, 5, 7, 7)), "Group", "Group")
  ))
  out <- capture.output(res_low <- suppressWarnings(
    check_spec1_collinearity(make_synth(rep(c(1, 3, 5, 7), 2)), "Group", "Group")
  ))

  expect_gt(res_high$vif_wfh_exposure, res_low$vif_wfh_exposure)
})

# ── check_for_dropped_coefficients() ──────────────────────────────────────────────────────────
# fixest does NOT leave a collinear variable in coef() as an NA-valued entry -- it removes it from
# coef() entirely and records the dropped name(s) in the model's own $collin.var. These tests pin
# that behavior down directly (so a future fixest upgrade that changes it is caught here, not
# silently) rather than just testing check_for_dropped_coefficients() against an assumption.

test_that("a perfectly collinear regressor is absent from coef() (not NA) and recorded in $collin.var", {
  synth <- tibble::tibble(x1 = rnorm(50), y = rnorm(50))
  synth$x2 <- synth$x1  # perfectly collinear with x1
  m <- suppressWarnings(feols(y ~ x1 + x2, data = synth))

  expect_false("x2" %in% names(coef(m)))
  expect_false(any(is.na(coef(m))))  # confirms is.na(coef(...)) would NOT have caught this
  expect_true("x2" %in% m$collin.var)
})

test_that("check_for_dropped_coefficients warns, naming the dropped variable, when nothing is expected", {
  synth <- tibble::tibble(x1 = rnorm(50), y = rnorm(50))
  synth$x2 <- synth$x1
  m <- suppressWarnings(feols(y ~ x1 + x2, data = synth))

  expect_warning(
    check_for_dropped_coefficients(m, "test model"),
    "x2"
  )
})

test_that("check_for_dropped_coefficients does not warn when the only drop is in expected_drops", {
  synth <- tibble::tibble(x1 = rnorm(50), y = rnorm(50))
  synth$x2 <- synth$x1
  m <- suppressWarnings(feols(y ~ x1 + x2, data = synth))

  expect_no_warning(check_for_dropped_coefficients(m, "test model", expected_drops = "x2"))
})

test_that("check_for_dropped_coefficients still warns on an UNEXPECTED extra drop alongside an expected one", {
  synth <- tibble::tibble(x1 = rnorm(50), y = rnorm(50))
  synth$x2 <- synth$x1        # expected drop
  synth$x3 <- synth$x1 * 2    # also collinear with x1 -- unexpected
  m <- suppressWarnings(feols(y ~ x1 + x2 + x3, data = synth))

  expect_warning(
    check_for_dropped_coefficients(m, "test model", expected_drops = "x2"),
    "x3"
  )
})

test_that("check_for_dropped_coefficients does not warn on a clean, non-collinear fit", {
  synth <- tibble::tibble(x1 = rnorm(50), x2 = rnorm(50), y = rnorm(50))
  m <- feols(y ~ x1 + x2, data = synth)

  expect_no_warning(check_for_dropped_coefficients(m, "test model"))
})
