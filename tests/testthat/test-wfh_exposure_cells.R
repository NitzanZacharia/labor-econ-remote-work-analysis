# test-wfh_exposure_cells.R
# Unit tests for the local wfh_exposure_cells.R addition: calibrate_isco_exposure() (the
# statistically-grounded swap test that replaced an earlier flat n-floor / ad hoc gap-threshold
# rule) and build_exposure_cells() (the pre-period shift-share exposure used as the primary DDD
# regressor in main.R, since it's defined for employed and non-employed rows alike).

test_that("calibrate_isco_exposure: a large, well-powered gap is swapped", {
  synth <- tibble::tibble(
    ShnatSeker = rep(c(2022, 2023), length.out = 500), Employed = 1L,
    MishlachYad_ISCO_08_2 = 100,
    WFH = rep(c(1, 0), c(450, 50)),          # realized ~0.9
    IDPUF = rep(seq_len(250), length.out = 500)
  )
  dn <- tibble::tibble(ISCO2 = 100, tele_ext = 0.1)   # gap ~0.8, well above 0.5

  res <- calibrate_isco_exposure(synth, dn)

  expect_true(res$swap)
  expect_equal(res$wfh_exposure_calibrated, res$realized_wfh)
  expect_false(res$wfh_exposure_calibrated == res$tele_ext)
})

test_that("calibrate_isco_exposure: a large raw gap on a thin/noisy cell is NOT swapped", {
  # Same magnitude of raw gap as the occupation above (theoretical 0, realized 0.75), but n = 4 --
  # too little data for the estimate to be statistically distinguishable from the 0.5 threshold,
  # even though the point estimate alone looks dramatic. This is the ISCO-63 case from the real
  # data (subsistence farmers, n=4, swapped 0.000->0.750 under the old flat-threshold rule).
  synth <- tibble::tibble(
    ShnatSeker = 2022, Employed = 1L, MishlachYad_ISCO_08_2 = 200,
    WFH = c(1, 1, 1, 0), IDPUF = 1:4
  )
  dn <- tibble::tibble(ISCO2 = 200, tele_ext = 0.0)

  res <- calibrate_isco_exposure(synth, dn)

  expect_false(res$swap)
  expect_equal(res$wfh_exposure_calibrated, res$tele_ext)
  expect_equal(res$gap, 0.75)  # the raw gap really is that large -- it's the power that fails
})

test_that("calibrate_isco_exposure: a small gap is never swapped, regardless of sample size", {
  synth <- tibble::tibble(
    ShnatSeker = rep(c(2022, 2023), length.out = 500), Employed = 1L,
    MishlachYad_ISCO_08_2 = 300,
    WFH = rep(c(1, 0), c(300, 200)),          # realized 0.6
    IDPUF = rep(seq_len(250), length.out = 500)
  )
  dn <- tibble::tibble(ISCO2 = 300, tele_ext = 0.5)   # gap 0.1, well under 0.5

  res <- calibrate_isco_exposure(synth, dn)

  expect_false(res$swap)
  expect_equal(res$wfh_exposure_calibrated, res$tele_ext)
})

test_that("calibrate_isco_exposure: occupations absent from ref_year keep their theoretical value, not NA", {
  synth <- tibble::tibble(
    ShnatSeker = 2022, Employed = 1L, MishlachYad_ISCO_08_2 = 100,
    WFH = 1, IDPUF = 1
  )
  dn <- tibble::tibble(ISCO2 = c(100, 999), tele_ext = c(0.5, 0.5))

  res <- calibrate_isco_exposure(synth, dn)

  row999 <- res[res$ISCO2 == 999, ]
  expect_false(row999$swap)
  expect_equal(row999$wfh_exposure_calibrated, 0.5)
  expect_true(is.na(row999$realized_wfh))
})

test_that("build_exposure_cells: 100% coverage for cells seen pre-period, NA for cells that aren't", {
  dn <- tibble::tibble(ISCO2 = c(100, 200, 300), tele_ext = c(0.8, 0.2, 0.5))

  # Pre-period (2017-2019), employed only -- what build_exposure_cells() is built from.
  pre <- tibble::tibble(
    ShnatSeker = 2018, Muasak = 1,
    Min = 2, GilNK = c(4, 4, 5), TeudaGvoha = c("X", "X", "Y"),
    MachozMegurim = c(1, 1, 2), MishlachYad_ISCO_08_2 = c(100, 200, 300),
    MishkalSofi = 1
  )
  cells <- build_exposure_cells(pre, dn)

  expect_equal(nrow(cells), 2)  # 2 distinct demographic cells above
  # cell (2,4,X,1) averages occupations 100 (0.8) and 200 (0.2) -> 0.5
  expect_equal(cells$WFH_Exposure[cells$GilNK == 4], 0.5)
  # cell (2,5,Y,2) is occupation 300 alone -> its own tele_ext
  expect_equal(cells$WFH_Exposure[cells$GilNK == 5], 0.5)

  # A post-period frame: two rows in cells seen pre-period (one non-employed, one employed with a
  # different occupation than pre-period -- the cell value must not depend on which occupation the
  # row itself holds), and one row in a cell never observed pre-period.
  full <- dplyr::bind_rows(
    tibble::tibble(ShnatSeker = 2022, Min = 2, GilNK = 4, TeudaGvoha = "X", MachozMegurim = 1),
    tibble::tibble(ShnatSeker = 2022, Min = 2, GilNK = 5, TeudaGvoha = "Y", MachozMegurim = 2),
    tibble::tibble(ShnatSeker = 2022, Min = 2, GilNK = 6, TeudaGvoha = "Z", MachozMegurim = 3)
  )
  joined <- full %>% dplyr::left_join(cells, by = c("Min", "GilNK", "TeudaGvoha", "MachozMegurim"))

  expect_equal(joined$WFH_Exposure[joined$GilNK == 4], 0.5)
  expect_equal(joined$WFH_Exposure[joined$GilNK == 5], 0.5)
  expect_true(is.na(joined$WFH_Exposure[joined$GilNK == 6]))
})
