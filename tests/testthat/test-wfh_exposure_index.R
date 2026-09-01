# test-wfh_exposure_index.R
# Checkpoint 6: unit test for build_wfh_exposure_index() using a small synthetic occupation-level
# fixture with known WFH shares, confirming the aggregation math directly (hand-computable, no
# fixture-CSV round trip needed since this function operates on an already-cleaned tibble).

make_synth <- function() {
  tibble::tibble(
    ShnatSeker              = c(rep(2021, 12), rep(2019, 3), rep(2021, 2)),
    Employed                = c(rep(1L, 12), rep(1L, 3), 0L, 1L),
    MishlachYad_ISCO_08_2   = c(rep(100, 4), rep(200, 3), rep(300, 5), rep(100, 3), 200, NA),
    WFH                     = c(
      1, 1, 0, 0,      # occupation 100, 2021, Employed==1: exposure 0.5, n=4
      1, 1, 1,          # occupation 200, 2021, Employed==1: exposure 1.0, n=3 (before the extra rows below)
      0, 0, 0, 0, 0,    # occupation 300, 2021, Employed==1: exposure 0.0, n=5
      NA, NA, NA,       # occupation 100, 2019 (pre-2021: WFH is NA) -- must be excluded by ref_year
      1,                # occupation 200, 2021, but Employed==0 -- must be excluded
      1                 # occupation NA (unknown), 2021, Employed==1 -- must be excluded (NA isco)
    )
  )
}

test_that("build_wfh_exposure_index computes the correct per-occupation WFH share and n", {
  idx <- build_wfh_exposure_index(make_synth())

  expect_setequal(idx$occupation_code, c(100, 200, 300))

  row100 <- idx[idx$occupation_code == 100, ]
  expect_equal(row100$wfh_exposure, 0.5)
  expect_equal(row100$n, 4)

  row200 <- idx[idx$occupation_code == 200, ]
  expect_equal(row200$wfh_exposure, 1.0)
  expect_equal(row200$n, 3)

  row300 <- idx[idx$occupation_code == 300, ]
  expect_equal(row300$wfh_exposure, 0.0)
  expect_equal(row300$n, 5)
})

test_that("build_wfh_exposure_index excludes pre-ref_year, non-employed, and unknown-occupation rows", {
  idx <- build_wfh_exposure_index(make_synth())
  # total n across all occupations must be exactly 4+3+5=12, not more (the excluded rows above
  # must not silently inflate any group's n or appear as a spurious NA-occupation group)
  expect_equal(sum(idx$n), 12)
  expect_false(any(is.na(idx$occupation_code)))
})

test_that("build_wfh_exposure_index is sorted by descending wfh_exposure", {
  idx <- build_wfh_exposure_index(make_synth())
  expect_equal(idx$wfh_exposure, sort(idx$wfh_exposure, decreasing = TRUE))
})

test_that("build_wfh_exposure_index respects a custom ref_year", {
  synth <- make_synth()
  # code 100's 2019 rows have WFH==NA (correctly, since WFH is undefined pre-2021) so pointing
  # ref_year at 2019 should yield no rows for occupation 100 at all
  idx_2019 <- build_wfh_exposure_index(synth, ref_year = 2019)
  expect_false(100 %in% idx_2019$occupation_code)
})
