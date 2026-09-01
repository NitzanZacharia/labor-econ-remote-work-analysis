# test-ddd_regression.R
# Checkpoint 7: contract tests for run_ddd_regression(), extending the exact hand-computable DiD
# pattern from test-basic_regression.R / test-intensive_margin_regression.R across 3 synthetic
# occupations whose beta_j (Mother:Post effect) is, by construction, an exact linear function of
# wfh_exposure -- gamma_0 = 0.10, gamma_1 = 0.40 -- so Model 2 (lm(beta_j ~ wfh_exposure)) should
# recover both exactly (3 points perfectly on a line).

make_occupation_data <- function(occupation_code, ones_in_11_cell) {
  make_cell <- function(mother, post, employed_vec) {
    n <- length(employed_vec)
    ctrl <- factor(rep(c("A", "B"), length.out = n))
    tibble::tibble(
      Mother = mother, Post = post, Employed = employed_vec,
      MatzavMishpachti = ctrl, Dat = ctrl, GilNK = ctrl, MachozMegurim = ctrl, TeudaGvoha = ctrl,
      MishlachYad_ISCO_08_2 = occupation_code
    )
  }
  dplyr::bind_rows(
    make_cell(0, 0, rep(0L, 20)),
    make_cell(0, 1, rep(0L, 20)),
    make_cell(1, 0, rep(0L, 20)),
    make_cell(1, 1, c(rep(1L, ones_in_11_cell), rep(0L, 20 - ones_in_11_cell)))
  )
}

make_synth <- function() {
  panel <- dplyr::bind_rows(
    make_occupation_data(1001, 2),   # beta_j = 2/20  = 0.10
    make_occupation_data(1002, 6),   # beta_j = 6/20  = 0.30
    make_occupation_data(1003, 10)   # beta_j = 10/20 = 0.50
  )
  panel$IDPUF <- seq_len(nrow(panel))

  exposure <- tibble::tibble(
    occupation_code = c(1001, 1002, 1003),
    wfh_exposure     = c(0.0, 0.5, 1.0),
    n                = c(80, 80, 80)
  )
  list(panel = panel, exposure = exposure)
}

test_that("run_ddd_regression returns the documented structure and both models fit", {
  synth <- make_synth()
  out <- capture.output(res <- suppressWarnings(run_ddd_regression(synth$panel, synth$exposure)))

  expect_type(res, "list")
  expect_true(all(c("table", "models", "mechanism_data") %in% names(res)))
  expect_s3_class(res$models$ddd, "fixest")
  expect_s3_class(res$models$mechanism, "lm")
})

test_that("Model 1's formula includes the full Mother*Post*WFH_Exposure interaction term set", {
  synth <- make_synth()
  out <- capture.output(res <- suppressWarnings(run_ddd_regression(synth$panel, synth$exposure)))
  coefs <- names(coef(res$models$ddd))

  expect_true("Mother" %in% coefs)
  expect_true("Post" %in% coefs)
  expect_true("WFH_Exposure" %in% coefs)
  expect_true("Mother:Post" %in% coefs)
  expect_true("Mother:WFH_Exposure" %in% coefs)
  expect_true("Post:WFH_Exposure" %in% coefs)
  expect_true("Mother:Post:WFH_Exposure" %in% coefs)
})

test_that("Model 2 recovers the exact gamma_0/gamma_1 from a perfectly-linear synthetic mechanism", {
  synth <- make_synth()
  out <- capture.output(res <- suppressWarnings(run_ddd_regression(synth$panel, synth$exposure)))

  co <- coef(res$models$mechanism)
  expect_equal(unname(co[["(Intercept)"]]), 0.10, tolerance = 1e-8)
  expect_equal(unname(co[["wfh_exposure"]]), 0.40, tolerance = 1e-8)
  expect_equal(nrow(res$mechanism_data), 3)  # all 3 occupations' beta_j used, none dropped
})

test_that("run_ddd_regression drops (and reports) an occupation where Mother:Post can't be estimated", {
  synth <- make_synth()
  # a degenerate 4th occupation: a single row, so Mother/Post/every control is constant --
  # basic_reg() cannot produce a meaningful Mother:Post estimate for it.
  degenerate_row <- tibble::tibble(
    Mother = 1, Post = 1, Employed = 1L,
    MatzavMishpachti = factor("A"), Dat = factor("A"), GilNK = factor("A"),
    MachozMegurim = factor("A"), TeudaGvoha = factor("A"),
    MishlachYad_ISCO_08_2 = 9999, IDPUF = 99999
  )
  panel_plus <- dplyr::bind_rows(synth$panel, degenerate_row)
  exposure_plus <- dplyr::bind_rows(
    synth$exposure, tibble::tibble(occupation_code = 9999, wfh_exposure = 0.9, n = 1)
  )

  expect_message(
    out <- capture.output(res <- suppressWarnings(run_ddd_regression(panel_plus, exposure_plus))),
    "1 of 4"
  )
  expect_equal(nrow(res$mechanism_data), 3)
  expect_false(9999 %in% res$mechanism_data$occupation_code)
})
