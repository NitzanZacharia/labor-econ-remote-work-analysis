# test-intensive_margin_lee_bounds.R
# Unit tests for run_intensive_margin_lee_bounds() (the DiD-adapted Lee (2009) trimming-bounds
# correction for intensive_margin_regression.R's Employed==1 conditioning). Two synthetic designs:
# one with no differential selection (bounds must collapse exactly to the point estimate), and one
# with a hand-constructed excess-selection cell where the trimmed lower/upper bounds are exactly
# hand-computable from the two subgroups making up that cell.

make_lee_bounds_row <- function(mother, post, employed, hours, ctrl) {
  tibble::tibble(
    Mother = mother, Post = post, Employed = employed, WorkHoursCont = hours,
    MatzavMishpachti = ctrl, Dat = ctrl, GilNK = ctrl, MachozMegurim = ctrl, TeudaGvoha = ctrl
  )
}

# load_and_clean_data(fixtures_dir)'s ~20 rows are sized for schema/parsing tests, not for a
# saturated Mother:Post + all 5 DEFAULT_CONTROLS dummy sets to be identified (mirrors the same
# fixture-power caveat test-gender_placebo.R's own docstring already documents for its DDD
# placebo) -- against them, fixest's collinearity screening drops Mother:Post entirely rather than
# just some control levels. A dedicated, adequately-sized synthetic panel with real random
# variation in every control (matching test-balance_test.R's make_balance_panel() convention)
# gives Mother:Post room to survive while still exercising the real function end to end.
make_lee_bounds_synth_panel <- function() {
  set.seed(55)
  n <- 400
  tibble::tibble(
    Mother = sample(0:1, n, replace = TRUE),
    Post   = sample(0:1, n, replace = TRUE),
    Employed = stats::rbinom(n, 1, 0.7),
    MatzavMishpachti = factor(sample(1:5, n, replace = TRUE)),
    Dat               = factor(sample(1:5, n, replace = TRUE)),
    GilNK             = factor(sample(3:7, n, replace = TRUE)),
    MachozMegurim     = factor(sample(1:7, n, replace = TRUE)),
    TeudaGvoha        = factor(sample(c("A", "B", "C"), n, replace = TRUE))
  ) %>%
    dplyr::mutate(
      WorkHoursCont = ifelse(Employed == 1, stats::rnorm(dplyr::n(), 40, 8), NA_real_),
      IDPUF = dplyr::row_number()
    )
}

test_that("run_intensive_margin_lee_bounds returns the documented structure and fits on a well-powered panel", {
  panel <- make_lee_bounds_synth_panel()
  out <- capture.output(res <- run_intensive_margin_lee_bounds(panel))

  expect_type(res, "list")
  expect_true(all(c("table", "models", "diagnostics") %in% names(res)))
  expect_s3_class(res$models$point, "fixest")
  expect_s3_class(res$models$lower, "fixest")
  expect_s3_class(res$models$upper, "fixest")
})

test_that("run_intensive_margin_lee_bounds emits a message summarizing selection rates", {
  panel <- make_lee_bounds_synth_panel()
  expect_message(out <- capture.output(res <- run_intensive_margin_lee_bounds(panel)), "selection")
})

test_that("bounds collapse exactly to the point estimate when there is no excess selection", {
  ctrl <- factor(rep(c("A", "B"), length.out = 100))
  make_cell <- function(mother, post) {
    make_lee_bounds_row(
      mother, post,
      employed = rep(c(1L, 0L), c(50, 50)),
      # Alternating +-1 around 40 (mean exactly 40, so the hand-computable "collapses to 40"
      # arithmetic below is untouched) rather than a literal constant 40 -- a flat value across
      # every employed row in every cell makes WorkHoursCont globally constant and feols refuses
      # to fit at all ("The dependent variable is a constant").
      hours    = c(rep(c(39, 41), length.out = 50), rep(NA_real_, 50)),
      ctrl     = ctrl
    )
  }
  synth <- dplyr::bind_rows(make_cell(0, 0), make_cell(0, 1), make_cell(1, 0), make_cell(1, 1))
  synth$IDPUF <- seq_len(nrow(synth))

  out <- capture.output(res <- suppressWarnings(run_intensive_margin_lee_bounds(synth)))

  expect_false(res$diagnostics$excess_selection)
  expect_equal(res$diagnostics$n_trimmed, 0L)
  co <- function(m) coef(m)[["Mother:Post"]]
  expect_equal(co(res$models$lower), co(res$models$point))
  expect_equal(co(res$models$upper), co(res$models$point))
})

test_that("excess selection in Mother==1,Post==1 produces hand-computable lower/upper bounds", {
  # Selection rates by construction: s00 = s01 = s10 = 0.5, s11 = 70/100 = 0.7, so
  # s11_counterfactual = 0.5 + (0.5 - 0.5) = 0.5 and trim_prop = 1 - 0.5/0.7 = 2/7 -> n_trim = 20
  # (floor(2/7 * 70) = 20).
  ctrl_core  <- factor(rep(c("A", "B"), length.out = 50))
  ctrl_extra <- factor(rep(c("A", "B"), length.out = 20))
  ctrl_unemp <- factor(rep(c("A", "B"), length.out = 50))

  # base_cell (the 3 untreated cells) uses alternating +-1 hours around 40 -- mean still exactly
  # 40, so none of the hand-computed bounds below change -- purely so the full sample isn't
  # literally constant at 40 once the treated cell's own two exact values (40 core / 10 excess,
  # left untouched below) get trimmed down to all-40 for the upper bound; a fully constant
  # dependent variable makes feols refuse to fit at all. treated_cell keeps its original flat
  # values unchanged, since the ranking/trimming arithmetic in the comments below depends on it.
  base_cell <- function(mother, post) dplyr::bind_rows(
    make_lee_bounds_row(mother, post, rep(1L, 50), rep(c(39, 41), length.out = 50), ctrl_core),
    make_lee_bounds_row(mother, post, rep(0L, 50), rep(NA_real_, 50), ctrl_unemp)
  )

  treated_cell <- dplyr::bind_rows(
    make_lee_bounds_row(1, 1, rep(1L, 50), rep(40, 50), ctrl_core),         # "core" employed mothers
    make_lee_bounds_row(1, 1, rep(1L, 20), rep(10, 20), ctrl_extra),        # 20 excess/marginal entrants
    make_lee_bounds_row(1, 1, rep(0L, 30), rep(NA_real_, 30), ctrl_unemp[1:30])
  )

  synth <- dplyr::bind_rows(base_cell(0, 0), base_cell(0, 1), base_cell(1, 0), treated_cell)
  synth$IDPUF <- seq_len(nrow(synth))

  out <- capture.output(res <- suppressWarnings(run_intensive_margin_lee_bounds(synth)))

  expect_true(res$diagnostics$excess_selection)
  expect_equal(res$diagnostics$n_trimmed, 20)

  co <- function(m) unname(coef(m)[["Mother:Post"]])
  # Point: cellMean(1,1) = (50*40 + 20*10)/70 = 2200/70; DiD = 2200/70 - 40 - 40 + 40
  expect_equal(co(res$models$point), 2200 / 70 - 40, tolerance = 1e-8)
  # Lower bound: trim the 20 highest-hours rows (the "40"s) -> (30*40+20*10)/50 = 28; DiD = -12
  expect_equal(co(res$models$lower), -12, tolerance = 1e-8)
  # Upper bound: trim the 20 lowest-hours rows (the "10"s) -> all 50 remaining rows are 40; DiD = 0
  expect_equal(co(res$models$upper), 0, tolerance = 1e-8)
  expect_lte(co(res$models$lower), co(res$models$point))
  expect_lte(co(res$models$point), co(res$models$upper))
})

test_that("run_intensive_margin_lee_bounds errors informatively when a (Mother, Post) cell is entirely empty", {
  ctrl <- factor(rep(c("A", "B"), length.out = 20))
  synth <- dplyr::bind_rows(
    make_lee_bounds_row(0, 0, rep(1L, 20), rep(40, 20), ctrl),
    make_lee_bounds_row(1, 1, rep(1L, 20), rep(40, 20), ctrl)
    # Mother=0,Post=1 and Mother=1,Post=0 are entirely missing.
  )
  synth$IDPUF <- seq_len(nrow(synth))
  expect_error(run_intensive_margin_lee_bounds(synth), "no rows found")
})
