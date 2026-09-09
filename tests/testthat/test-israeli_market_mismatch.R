# test-israeli_market_mismatch.R
# Unit tests for check_market_mismatch() (israeli_market_mismatch.R) -- a thin descriptive wrapper
# around calibrate_isco_exposure() (already unit-tested in test-wfh_exposure_cells.R). These tests
# only verify the wrapper's OWN logic (the israel_vs_us_gap/abs_mismatch columns it adds, the
# descending sort by abs_mismatch, and that `...` reaches calibrate_isco_exposure()), not
# calibrate_isco_exposure()'s internal statistics again.
#
# build_exposure_isco2() (wfh_exposure_cells.R) reads a hardcoded "israeli_cbs_wfh_2digit.csv"
# from the working directory by default -- that file isn't present in this environment (a known,
# separately-tracked gap, not something these tests are meant to catch or paper over). To make
# check_market_mismatch() testable without it, both functions now take an explicit path /
# exposure_path parameter (default unchanged, so real usage via run_mismatch.R is unaffected);
# these tests write a small temporary CSV and pass its path in instead.

make_mismatch_occ <- function(code, idpuf_offset, wfh_ones, n = 500) {
  tibble::tibble(
    ShnatSeker = rep(c(2022, 2023), length.out = n), Employed = 1L,
    MishlachYad_ISCO_08_2 = code,
    WFH = rep(c(1, 0), c(wfh_ones, n - wfh_ones)),
    IDPUF = idpuf_offset + rep(seq_len(n / 2), length.out = n)
  )
}

test_that("check_market_mismatch adds israel_vs_us_gap/abs_mismatch and sorts by descending abs_mismatch", {
  tmp_csv <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp_csv), add = TRUE)
  readr::write_csv(
    tibble::tibble(isco_2digit = c(100, 200), wfh_probability_2d = c(0.1, 0.5)),
    tmp_csv
  )

  # ISCO 100: tele_ext = 0.1, realized = 450/500 = 0.9 -> gap = 0.8
  # ISCO 200: tele_ext = 0.5, realized = 300/500 = 0.6 -> gap = 0.1
  synth <- dplyr::bind_rows(
    make_mismatch_occ(100, 0,    450),
    make_mismatch_occ(200, 1000, 300)
  )

  out <- capture.output(res <- suppressWarnings(
    check_market_mismatch(synth, exposure_path = tmp_csv)
  ))

  expect_true(all(c("israel_vs_us_gap", "abs_mismatch") %in% names(res)))
  expect_equal(res$abs_mismatch, res$gap)  # abs_mismatch is a direct alias of calibrate_isco_exposure()'s gap
  expect_equal(res$israel_vs_us_gap, res$realized_wfh - res$tele_ext, tolerance = 1e-8)

  # descending abs_mismatch: ISCO 100 (gap 0.8) before ISCO 200 (gap 0.1)
  expect_equal(res$ISCO2, c(100, 200))
  expect_equal(res$abs_mismatch, c(0.8, 0.1), tolerance = 1e-8)
})

test_that("check_market_mismatch passes ... through to calibrate_isco_exposure (e.g. a custom gap_threshold)", {
  tmp_csv <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp_csv), add = TRUE)
  readr::write_csv(tibble::tibble(isco_2digit = 100, wfh_probability_2d = 0.1), tmp_csv)

  synth <- make_mismatch_occ(100, 0, 450)

  # A very high gap_threshold (0.99) means even this occupation's 0.8 gap should NOT be swapped,
  # unlike calibrate_isco_exposure()'s own default gap_threshold = 0.5.
  out <- capture.output(res <- suppressWarnings(
    check_market_mismatch(synth, exposure_path = tmp_csv, gap_threshold = 0.99)
  ))
  expect_false(res$swap)
})

test_that("build_exposure_isco2's path parameter defaults to the real project data file", {
  expect_equal(formals(build_exposure_isco2)$path, "israeli_cbs_wfh_2digit.csv")
})

test_that("the run_mismatch.R sequence (build -> check -> write_csv) round-trips through a CSV intact", {
  # run_mismatch.R itself hardcodes readRDS("csvs/cleaned_df.rds") and a fixed output path, so
  # (like test-pipeline_smoke.R does for main.R) it's mirrored here rather than sourced directly:
  # a tempfile stands in for both the exposure crosswalk and the write_csv() destination.
  tmp_csv <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp_csv), add = TRUE)
  readr::write_csv(
    tibble::tibble(isco_2digit = c(100, 200), wfh_probability_2d = c(0.1, 0.5)),
    tmp_csv
  )
  synth <- dplyr::bind_rows(
    make_mismatch_occ(100, 0,    450),
    make_mismatch_occ(200, 1000, 300)
  )

  out <- capture.output(mismatch_table <- suppressWarnings(
    check_market_mismatch(synth, exposure_path = tmp_csv)
  ))

  out_csv <- tempfile(fileext = ".csv")
  on.exit(unlink(out_csv), add = TRUE)
  readr::write_csv(mismatch_table, out_csv)
  reloaded <- readr::read_csv(out_csv, show_col_types = FALSE)

  expect_equal(nrow(reloaded), nrow(mismatch_table))
  expect_true(all(c(
    "ISCO2", "tele_ext", "realized_wfh", "gap", "swap",
    "wfh_exposure_calibrated", "israel_vs_us_gap", "abs_mismatch"
  ) %in% names(reloaded)))
})
