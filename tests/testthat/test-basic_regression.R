# test-basic_regression.R
# Priority 2: basic_reg() and basic_reg_comp() contract tests, plus a hand-computable synthetic
# DiD check on a saturated 2x2 design (exact arithmetic, no simulation/randomness needed).

cleaned <- load_and_clean_data(fixtures_dir)

test_that("basic_reg returns the documented structure and fits on fixture data", {
  # NB: with only ~21 rows spread across 5 sparse categorical controls, the fixture is small
  # enough that fixest can legitimately drop the Mother:Post term to collinearity (an artifact of
  # fixture size, not a defect -- this never happens on the real 372k-row dataset). The exact
  # DiD coefficient itself is checked below on a purpose-built synthetic design instead.
  out <- capture.output(res <- basic_reg(cleaned))
  expect_type(res, "list")
  expect_true(all(c("table", "models") %in% names(res)))
  expect_s3_class(res$models$employed, "fixest")

  coefs <- names(coef(res$models$employed))
  expect_true("Mother" %in% coefs)
  expect_true("Post" %in% coefs)
})

test_that("basic_reg recovers an exact hand-computable DiD effect on a saturated synthetic design", {
  # Employed ~ Mother + Post + Mother:Post is fully saturated for a balanced 2x2 design (4 free
  # parameters, 4 cells) -- OLS fits cell means exactly, so Mother:Post must equal exactly
  # cellMean(1,1) - cellMean(1,0) - cellMean(0,1) + cellMean(0,0) = 0.3 - 0 - 0 + 0 = 0.3.
  # Controls get a balanced 2-level factor (rep(c("A","B"), length.out=n), applied in the same row
  # order as the outcome vector) so every level is a 2+-level factor (required by R's contrast
  # system) while staying exactly orthogonal to Employed within every cell -- preserving the exact
  # 0.3 result algebraically (Frisch-Waugh-Lovell): in the one cell with outcome variation
  # (Mother=1,Post=1: 6 ones then 14 zeros), the alternating A/B split is exactly 3-A/3-B among
  # the ones and 7-A/7-B among the zeros, so each level's within-cell mean is identical.
  make_cell <- function(mother, post, employed_vec) {
    n <- length(employed_vec)
    ctrl <- factor(rep(c("A", "B"), length.out = n))
    tibble::tibble(
      Mother = mother, Post = post, Employed = employed_vec,
      MatzavMishpachti = ctrl, Dat = ctrl, GilNK = ctrl,
      MachozMegurim = ctrl, TeudaGvoha = ctrl
    )
  }
  synth <- dplyr::bind_rows(
    make_cell(0, 0, rep(0L, 20)),
    make_cell(0, 1, rep(0L, 20)),
    make_cell(1, 0, rep(0L, 20)),
    make_cell(1, 1, c(rep(1L, 6), rep(0L, 14)))  # mean 0.3
  )
  synth$IDPUF <- seq_len(nrow(synth))

  out <- capture.output(res <- suppressWarnings(basic_reg(synth)))
  did_coef <- coef(res$models$employed)[["Mother:Post"]]
  expect_equal(did_coef, 0.3, tolerance = 1e-8)
})

test_that("basic_reg_comp returns the documented structure and fits both models on fixture data", {
  out <- capture.output(res <- basic_reg_comp(cleaned))
  expect_type(res, "list")
  expect_true(all(c("table", "models") %in% names(res)))
  expect_s3_class(res$models$employed, "fixest")
  expect_s3_class(res$models$employed_muasak, "fixest")
  # the Muasak-observed-only model must have fewer or equal observations than the full sample
  expect_lte(nobs(res$models$employed_muasak), nobs(res$models$employed))
})
