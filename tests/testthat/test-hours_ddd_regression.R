# test-hours_ddd_regression.R
# Unit tests for run_hours_ddd_regression() -- the intensive-margin (WorkHoursCont) counterpart to
# ddd_regression.R's run_ddd_regression(), using the PURE occupation-level WFH exposure measure
# (joined by MishlachYad_ISCO_08_2) rather than the demographic-cell-based WFH_Exposure the
# extensive-margin primary DDD uses. See docs/decisions/hours-ddd-pivot.md.

# 10 occupations with distinct, evenly-spaced occupation-level exposure. Controls, Mother, and Post
# are all independently sampled (matching test-intensive_margin_lee_bounds.R's
# make_lee_bounds_synth_panel() template) rather than built from rep()-based row patterns -- an
# earlier version of this fixture used rep() patterns for both the controls and Mother/Post and
# they turned out to share the same period/phase, making several controls exactly collinear with
# Mother across the whole panel. Independent random assignment over a large-enough sample avoids
# that by construction.
make_hours_ddd_fixtures <- function(delta = -3) {
  n_occ     <- 10
  occ_codes <- 300 + seq_len(n_occ)
  exposure_index <- tibble::tibble(
    occupation_code = occ_codes,
    wfh_exposure    = seq(0.05, 0.95, length.out = n_occ)
  )

  n <- 400
  occ_i <- sample(seq_len(n_occ), n, replace = TRUE)
  panel <- tibble::tibble(
    MishlachYad_ISCO_08_2 = occ_codes[occ_i],
    .wfh                  = exposure_index$wfh_exposure[occ_i],
    MatzavMishpachti = factor(sample(1:5, n, replace = TRUE)),
    Dat              = factor(sample(1:5, n, replace = TRUE)),
    GilNK            = factor(sample(3:7, n, replace = TRUE)),
    MachozMegurim    = factor(sample(1:7, n, replace = TRUE)),
    TeudaGvoha       = factor(sample(c("A", "B", "C"), n, replace = TRUE)),
    Mother   = sample(0:1, n, replace = TRUE),
    Post     = sample(0:1, n, replace = TRUE),
    Employed = 1L
  ) %>%
    dplyr::mutate(
      WorkHoursCont = 40 + delta * Mother * Post * .wfh + stats::rnorm(dplyr::n(), 0, 0.5),
      IDPUF = dplyr::row_number()
    ) %>%
    dplyr::select(-.wfh)

  list(panel = panel, exposure_index = exposure_index)
}

test_that("run_hours_ddd_regression recovers the correct sign of a known injected effect", {
  set.seed(11)
  fx  <- make_hours_ddd_fixtures(delta = -3)
  out <- capture.output(res <- suppressWarnings(run_hours_ddd_regression(fx$panel, fx$exposure_index)))

  expect_type(res, "list")
  expect_true(all(c("table", "model", "n_employed", "n_matched") %in% names(res)))
  expect_s3_class(res$model, "fixest")
  expect_true("Mother:Post:WFH_Exposure" %in% names(coef(res$model)))
  expect_lt(unname(coef(res$model)[["Mother:Post:WFH_Exposure"]]), 0)
  expect_equal(res$n_employed, nrow(fx$panel))
  expect_equal(res$n_matched, nrow(fx$panel))
})

test_that("run_hours_ddd_regression excludes non-employed and occupation-unmatched rows", {
  set.seed(12)
  fx <- make_hours_ddd_fixtures(delta = -3)

  extra_nonemployed <- fx$panel[1:5, ] %>% dplyr::mutate(Employed = 0L, WorkHoursCont = NA_real_)
  extra_unmatched    <- fx$panel[1:3, ] %>% dplyr::mutate(MishlachYad_ISCO_08_2 = 9999)
  panel2 <- dplyr::bind_rows(fx$panel, extra_nonemployed, extra_unmatched)

  out <- capture.output(res <- suppressWarnings(run_hours_ddd_regression(panel2, fx$exposure_index)))

  expect_equal(res$n_employed, nrow(fx$panel) + nrow(extra_unmatched))
  expect_equal(res$n_matched, nrow(fx$panel))
})

test_that("run_hours_ddd_regression flags unexpected collinear drops", {
  fx <- make_hours_ddd_fixtures(delta = -3)
  out <- capture.output(
    expect_no_warning(res <- run_hours_ddd_regression(fx$panel, fx$exposure_index))
  )
})
