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

# ── calibrate_isco_exposure: undefined-SE branches and parameters ────────────────────────────

test_that("calibrate_isco_exposure: an occupation whose rows share a single IDPUF gets an undefined SE and is not swapped", {
  # A repeat CBS respondent surveyed multiple times -- the real ISCO-63 case the function's own
  # comment describes (4 rows, all one person, all one IDPUF). n_distinct(IDPUF) < 2 means a
  # cluster-robust SE can't be computed at all, so the swap test can't run -- regardless of how
  # large the raw gap looks.
  synth <- tibble::tibble(
    ShnatSeker = 2022, Employed = 1L, MishlachYad_ISCO_08_2 = 400,
    WFH = c(1, 1, 1, 0), IDPUF = rep(1, 4)
  )
  dn <- tibble::tibble(ISCO2 = 400, tele_ext = 0.0)   # raw gap 0.75, well above 0.5

  res <- calibrate_isco_exposure(synth, dn)

  expect_equal(res$se_na_reason, "fewer than 2 distinct IDPUF")
  expect_true(is.na(res$se_clustered))
  expect_false(res$swap)
  expect_equal(res$wfh_exposure_calibrated, res$tele_ext)
})

test_that("calibrate_isco_exposure: an occupation with a constant outcome gets an undefined SE and is not swapped", {
  # >= 2 distinct IDPUF (so the first guard passes) but every respondent gives the same WFH
  # answer -- feols refuses an intercept-only fit on a constant DV, so this is the second
  # documented undefined-SE reason, distinct from the single-cluster case above.
  synth <- tibble::tibble(
    ShnatSeker = 2022, Employed = 1L, MishlachYad_ISCO_08_2 = 500,
    WFH = 1, IDPUF = 1:4
  )
  dn <- tibble::tibble(ISCO2 = 500, tele_ext = 0.0)   # raw gap 1.0

  res <- calibrate_isco_exposure(synth, dn)

  expect_equal(res$se_na_reason, "constant outcome within occupation")
  expect_true(is.na(res$se_clustered))
  expect_false(res$swap)
})

test_that("calibrate_isco_exposure: a higher conf_level requires stronger evidence and can flip a borderline swap to no-swap", {
  # A moderately-powered occupation (20 clusters, 2 obs each) with a gap just above the
  # threshold: well-powered enough to swap at the default 95% confidence, but not powered enough
  # to survive a much stricter one-sided test. z = qnorm(1 - (1-conf_level)/2) is monotonically
  # increasing in conf_level, so this also exercises that conf_level is actually threaded through
  # to the swap test rather than ignored.
  synth <- tibble::tibble(
    ShnatSeker = 2022, Employed = 1L, MishlachYad_ISCO_08_2 = 700,
    WFH = rep(c(1, 1, 0), length.out = 40),          # realized ~0.667
    IDPUF = rep(seq_len(20), each = 2)
  )
  dn <- tibble::tibble(ISCO2 = 700, tele_ext = 0.0)   # gap 0.675

  res_95  <- calibrate_isco_exposure(synth, dn, conf_level = 0.95)
  res_999 <- calibrate_isco_exposure(synth, dn, conf_level = 0.999)

  expect_true(res_95$swap)
  expect_false(res_999$swap)
  expect_lt(res_999$margin, res_95$margin)
})

test_that("calibrate_isco_exposure: wfh_col lets the outcome column be named something other than WFH", {
  synth <- tibble::tibble(
    ShnatSeker = rep(c(2022, 2023), length.out = 500), Employed = 1L,
    MishlachYad_ISCO_08_2 = 100,
    MyWFHVar = rep(c(1, 0), c(450, 50)),             # realized 0.9
    IDPUF = rep(seq_len(250), length.out = 500)
  )
  dn <- tibble::tibble(ISCO2 = 100, tele_ext = 0.1)

  res <- calibrate_isco_exposure(synth, dn, wfh_col = "MyWFHVar")

  expect_equal(res$realized_wfh, 0.9)
  expect_true(res$swap)

  # The default wfh_col ("WFH") isn't in this data at all -- confirms wfh_col genuinely
  # controls which column is read, rather than the function silently falling back to something
  # else.
  expect_error(calibrate_isco_exposure(synth, dn))
})

# ── build_exposure_cells: weighting, pivoting, and filter branches ───────────────────────────

test_that("build_exposure_cells: unequal MishkalSofi weights produce the correct weighted-mean cell exposure", {
  dn <- tibble::tibble(ISCO2 = c(100, 200), tele_ext = c(0.8, 0.2))
  pre <- tibble::tibble(
    ShnatSeker = 2018, Muasak = 1, Min = 2, GilNK = 4, TeudaGvoha = "X", MachozMegurim = 1,
    MishlachYad_ISCO_08_2 = c(100, 200), MishkalSofi = c(300, 100)
  )

  cells <- build_exposure_cells(pre, dn)

  # weighted.mean(c(0.8, 0.2), c(300, 100)) = (0.8*300 + 0.2*100) / 400 = 0.65
  expect_equal(cells$WFH_Exposure, 0.65, tolerance = 1e-8)
  expect_equal(cells$n_cell, 400)
})

test_that("build_exposure_cells: an ISCO2 code absent from the crosswalk is dropped before both the mean and n_cell", {
  dn <- tibble::tibble(ISCO2 = c(100, 200), tele_ext = c(0.8, 0.2))
  pre <- tibble::tibble(
    ShnatSeker = 2018, Muasak = 1, Min = 2, GilNK = 4, TeudaGvoha = "X", MachozMegurim = 1,
    MishlachYad_ISCO_08_2 = c(100, 200, 999),        # 999 isn't in the crosswalk
    MishkalSofi = c(300, 100, 1000)                  # a large decoy weight
  )

  cells <- build_exposure_cells(pre, dn)

  expect_equal(cells$WFH_Exposure, 0.65, tolerance = 1e-8)
  expect_equal(cells$n_cell, 400)
})

test_that("build_exposure_cells: Muasak != 1 rows are excluded from cell construction", {
  dn <- tibble::tibble(ISCO2 = c(100, 200), tele_ext = c(0.8, 0.2))
  pre <- tibble::tibble(
    ShnatSeker = 2018, Muasak = c(1, 1, 2), Min = 2, GilNK = 4, TeudaGvoha = "X",
    MachozMegurim = 1, MishlachYad_ISCO_08_2 = c(100, 200, 100),
    MishkalSofi = c(300, 100, 5000)                  # decoy: huge weight, not employed
  )

  cells <- build_exposure_cells(pre, dn)

  expect_equal(cells$WFH_Exposure, 0.65, tolerance = 1e-8)
  expect_equal(cells$n_cell, 400)
})

test_that("build_exposure_cells: ShnatSeker outside 2017:2019 is excluded from cell construction", {
  dn <- tibble::tibble(ISCO2 = c(100, 200), tele_ext = c(0.8, 0.2))
  pre <- tibble::tibble(
    ShnatSeker = c(2018, 2018, 2020), Muasak = 1, Min = 2, GilNK = 4, TeudaGvoha = "X",
    MachozMegurim = 1, MishlachYad_ISCO_08_2 = c(100, 200, 100),
    MishkalSofi = c(300, 100, 5000)                  # decoy: huge weight, outside the window
  )

  cells <- build_exposure_cells(pre, dn)

  expect_equal(cells$WFH_Exposure, 0.65, tolerance = 1e-8)
  expect_equal(cells$n_cell, 400)
})

test_that("build_exposure_cells: disclosure-masked ISCO2 codes coerce to NA and are dropped without leaking a warning", {
  # Mirrors the real CBS masking convention (generate_fixtures.R): thin occupation cells are
  # masked as literal strings like "XX"/"7X" rather than left blank.
  dn <- tibble::tibble(ISCO2 = c(100, 200), tele_ext = c(0.8, 0.2))
  pre <- tibble::tibble(
    ShnatSeker = 2018, Muasak = 1, Min = 2, GilNK = 4, TeudaGvoha = "X", MachozMegurim = 1,
    MishlachYad_ISCO_08_2 = c("100", "200", "XX", "7X"),
    MishkalSofi = c(300, 100, 9999, 9999)
  )

  expect_no_warning(cells <- build_exposure_cells(pre, dn))

  expect_equal(cells$WFH_Exposure, 0.65, tolerance = 1e-8)
  expect_equal(cells$n_cell, 400)
})
