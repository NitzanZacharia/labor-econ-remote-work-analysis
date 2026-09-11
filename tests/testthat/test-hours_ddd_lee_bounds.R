# test-hours_ddd_lee_bounds.R
# Unit tests for run_hours_ddd_lee_bounds() -- the generalization of
# intensive_margin_lee_bounds.R's DiD-adapted Lee (2009) trimming bounds to the triple-interaction
# hours DDD (Mother x Post x WFH_Exposure), stratified by quartile of the demographic-cell-based
# WFH_Exposure. See docs/decisions/hours-ddd-pivot.md and hours_ddd_lee_bounds.R's header comment
# for the two-measure design this exercises.
#
# Fixture design: a single demographic dimension (GilNK, 20 levels) doubles as the cell-based
# exposure's join key. exposure_cells assigns GilNK 1:20 an evenly-spaced WFH_Exposure from 0.025
# to 0.975 -- verified (see docs/decisions/hours-ddd-pivot.md) to place GilNK == 3/8/13/18 cleanly
# inside quartiles 1/2/3/4 respectively, away from any breakpoint. Those four GilNK levels each
# carry their own occupation code/occupation-level exposure (301-304) for the regression itself.
# The other 16 GilNK levels supply Mother==0,Post==0-only "calibration" rows (ShnatSeker < 2020, so
# compute_pre_period_quartile_breaks() sees enough distinct WFH_Exposure values to produce clean,
# non-duplicate breakpoints) split exactly 50/50 Employed, so they cannot shift any quartile's true
# selection rate away from the value the main design intends (weighted average of 0.5 and 0.5 is
# still 0.5) -- and are given no occupation code, so run_hours_ddd_regression()'s inner_join can
# never pull them into the actual estimation sample.
make_hours_lee_bounds_fixtures <- function(excess_in_q4 = TRUE) {
  reps <- tibble::tibble(
    quartile = 1:4, GilNK = c(3, 8, 13, 18), occ = c(301, 302, 303, 304),
    occ_wfh  = c(0.125, 0.375, 0.625, 0.875)
  )

  extra_gilnk_by_q <- list(`1` = c(1, 2, 4, 5), `2` = c(6, 7, 9, 10),
                            `3` = c(11, 12, 14, 15), `4` = c(16, 17, 19, 20))
  extras <- purrr::imap_dfr(extra_gilnk_by_q, function(gilnks, q) {
    tibble::tibble(
      GilNK = gilnks, ShnatSeker = 2018, Mother = 0, Post = 0,
      Employed = c(1L, 1L, 0L, 0L), WorkHoursCont = ifelse(Employed == 1, 40, NA_real_),
      MishlachYad_ISCO_08_2 = NA_real_, Ctrl = factor("A", levels = c("A", "B"))
    )
  })

  make_balanced_group <- function(gilnk, occ) {
    make_cell <- function(mother, post) tibble::tibble(
      GilNK = gilnk, ShnatSeker = 2022, Mother = mother, Post = post,
      Employed = rep(c(1L, 0L), c(20, 20)),
      WorkHoursCont = c(rep(c(39, 41), length.out = 20), rep(NA_real_, 20)),
      MishlachYad_ISCO_08_2 = c(rep(occ, 20), rep(NA_real_, 20)),
      Ctrl = factor(rep(c("A", "B"), length.out = 40), levels = c("A", "B"))
    )
    dplyr::bind_rows(make_cell(0, 0), make_cell(0, 1), make_cell(1, 0), make_cell(1, 1))
  }

  # Mirrors test-intensive_margin_lee_bounds.R's hand-computable design: s00=s01=s10=0.5,
  # s11=70/100=0.7 -> s11_counterfactual=0.5, trim_prop=2/7, n_trim=floor(2/7*70)=20.
  make_excess_group <- function(gilnk, occ) {
    base_cell <- function(mother, post) tibble::tibble(
      GilNK = gilnk, ShnatSeker = 2022, Mother = mother, Post = post,
      Employed = rep(c(1L, 0L), c(50, 50)),
      WorkHoursCont = c(rep(c(39, 41), length.out = 50), rep(NA_real_, 50)),
      MishlachYad_ISCO_08_2 = c(rep(occ, 50), rep(NA_real_, 50)),
      Ctrl = factor(rep(c("A", "B"), length.out = 100), levels = c("A", "B"))
    )
    treated_cell <- tibble::tibble(
      GilNK = gilnk, ShnatSeker = 2022, Mother = 1, Post = 1,
      Employed = c(rep(1L, 50), rep(1L, 20), rep(0L, 30)),
      WorkHoursCont = c(rep(40, 50), rep(10, 20), rep(NA_real_, 30)),
      MishlachYad_ISCO_08_2 = c(rep(occ, 70), rep(NA_real_, 30)),
      Ctrl = factor(rep(c("A", "B"), length.out = 100), levels = c("A", "B"))
    )
    dplyr::bind_rows(base_cell(0, 0), base_cell(0, 1), base_cell(1, 0), treated_cell)
  }

  groups <- purrr::pmap(reps, function(quartile, GilNK, occ, occ_wfh) {
    if (excess_in_q4 && quartile == 4) make_excess_group(GilNK, occ) else make_balanced_group(GilNK, occ)
  })

  full_panel <- dplyr::bind_rows(extras, dplyr::bind_rows(groups))
  full_panel$IDPUF <- seq_len(nrow(full_panel))

  list(
    cleaned_df     = full_panel,
    exposure_index = dplyr::select(reps, occupation_code = occ, wfh_exposure = occ_wfh),
    exposure_cells = tibble::tibble(GilNK = 1:20, WFH_Exposure = seq(0.025, 0.975, length.out = 20),
                                     n_cell = 50)
  )
}

test_that("run_hours_ddd_lee_bounds returns the documented structure", {
  fx  <- make_hours_lee_bounds_fixtures(excess_in_q4 = TRUE)
  out <- capture.output(res <- suppressWarnings(
    run_hours_ddd_lee_bounds(fx$cleaned_df, fx$exposure_index, fx$exposure_cells, controls = "Ctrl")
  ))

  expect_type(res, "list")
  expect_true(all(c("table", "models", "diagnostics", "imbens_manski_ci") %in% names(res)))
  expect_s3_class(res$models$point, "fixest")
  expect_s3_class(res$models$lower, "fixest")
  expect_s3_class(res$models$upper, "fixest")
  expect_equal(nrow(res$diagnostics$quartile_selection_rates), 4)
})

test_that("bounds collapse to the point estimate when no quartile has excess selection", {
  fx  <- make_hours_lee_bounds_fixtures(excess_in_q4 = FALSE)
  out <- capture.output(res <- suppressWarnings(
    run_hours_ddd_lee_bounds(fx$cleaned_df, fx$exposure_index, fx$exposure_cells, controls = "Ctrl")
  ))

  expect_false(any(res$diagnostics$quartile_selection_rates$excess_selection))
  expect_equal(res$diagnostics$n_trimmed_total, 0L)

  co <- function(m) unname(coef(m)[["Mother:Post:WFH_Exposure"]])
  expect_equal(co(res$models$lower), co(res$models$point), tolerance = 1e-8)
  expect_equal(co(res$models$upper), co(res$models$point), tolerance = 1e-8)

  # No excess anywhere -> the Imbens-Manski CI collapses to the ordinary +-1.96*se interval
  # (mirrors test-intensive_margin_lee_bounds.R's equivalent check).
  se_point <- unname(se(res$models$point)[["Mother:Post:WFH_Exposure"]])
  expect_equal(res$imbens_manski_ci$c_alpha, qnorm(0.975), tolerance = 1e-6)
})

test_that("excess selection concentrated in exactly one quartile trims only that quartile", {
  fx  <- make_hours_lee_bounds_fixtures(excess_in_q4 = TRUE)
  out <- capture.output(res <- suppressWarnings(
    run_hours_ddd_lee_bounds(fx$cleaned_df, fx$exposure_index, fx$exposure_cells, controls = "Ctrl")
  ))

  diag <- res$diagnostics$quartile_selection_rates
  expect_equal(diag$excess_selection, c(FALSE, FALSE, FALSE, TRUE))
  expect_equal(diag$trim_prop[diag$WFH_Exposure_Q %in% 1:3], c(0, 0, 0))
  expect_equal(diag$trim_prop[diag$WFH_Exposure_Q == 4], 2 / 7, tolerance = 1e-8)

  n_trim <- res$diagnostics$n_trimmed_by_quartile
  expect_equal(n_trim$n_trimmed[n_trim$WFH_Exposure_Q %in% 1:3], c(0L, 0L, 0L))
  expect_equal(n_trim$n_trimmed[n_trim$WFH_Exposure_Q == 4], 20L)
  expect_equal(res$diagnostics$n_trimmed_total, 20L)

  # Fully deterministic fixture (no RNG) -- exact values confirmed against a real run of this
  # design before being hard-coded here.
  co <- function(m) unname(coef(m)[["Mother:Post:WFH_Exposure"]])
  expect_equal(co(res$models$point), -13.0909090909, tolerance = 1e-6)
  expect_equal(co(res$models$lower), -17.5609756098, tolerance = 1e-6)
  expect_equal(co(res$models$upper), 0, tolerance = 1e-6)
  expect_lte(co(res$models$lower), co(res$models$point))
  expect_lte(co(res$models$point), co(res$models$upper))
})

test_that("run_hours_ddd_lee_bounds warns when a quartile's Mother=1,Post=1 cell is thin", {
  fx <- make_hours_lee_bounds_fixtures(excess_in_q4 = FALSE)
  # Thin out quartile 1's Mother=1,Post=1 cell to below MIN_CELL_WARN (30).
  thinned <- fx$cleaned_df %>%
    dplyr::filter(!(GilNK == 3 & Mother == 1 & Post == 1)) %>%
    dplyr::bind_rows(fx$cleaned_df %>%
      dplyr::filter(GilNK == 3, Mother == 1, Post == 1) %>%
      dplyr::slice(1:10))

  expect_warning(
    out <- capture.output(res <- run_hours_ddd_lee_bounds(thinned, fx$exposure_index, fx$exposure_cells, controls = "Ctrl")),
    "fewer than"
  )
})
