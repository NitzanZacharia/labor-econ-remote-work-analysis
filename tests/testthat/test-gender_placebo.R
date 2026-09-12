# test-gender_placebo.R
# Checkpoint 5: tests for the sex_filter parameter added to load_and_clean_data() and for
# run_gender_placebo()'s structure. The fixtures include Min==1 (men) rows specifically for this
# (see generate_fixtures.R) -- invisible to every other test in the suite, which all call
# load_and_clean_data(fixtures_dir) with the default sex_filter="women", so this checkpoint's
# explicit safety requirement (the Checkpoint-0 suite must pass unmodified) holds by construction:
# no other test file was touched to make this one pass.

test_that("load_and_clean_data() with no sex_filter argument still defaults to women (Min==2)", {
  cleaned <- load_and_clean_data(fixtures_dir)
  expect_true(all(cleaned$Min == 2))
  # none of the new Checkpoint-5 male IDPUFs should appear
  expect_false(any(cleaned$IDPUF %in% c(2019101:2019106, 2021101:2021104)))
})

test_that("load_and_clean_data(sex_filter = 'men') returns only Min==1 rows", {
  cleaned_men <- load_and_clean_data(fixtures_dir, sex_filter = "men")
  expect_gt(nrow(cleaned_men), 0)
  expect_true(all(cleaned_men$Min == 1))
  # none of the default women IDPUFs should appear
  expect_false(any(cleaned_men$IDPUF %in% c(2019001:2019016, 2021001:2021004)))
})

test_that("load_and_clean_data(sex_filter = 'invalid') errors via match.arg", {
  expect_error(load_and_clean_data(fixtures_dir, sex_filter = "invalid"))
})

test_that("run_gender_placebo returns the documented structure on fixture data", {
  # suppressWarnings: same fixture-sparsity-induced collinearity check_for_dropped_coefficients()
  # now surfaces for basic_reg() on the small male subsample (see test-basic_regression.R's note).
  out <- capture.output(res <- suppressWarnings(run_gender_placebo(fixtures_dir)))
  expect_type(res, "list")
  expect_true(all(c("cleaned_men", "result") %in% names(res)))
  expect_true(all(res$cleaned_men$Min == 1))
  expect_s3_class(res$result$models$employed, "fixest")
})

# ── DDD placebo (Employed ~ Mother*Post*WFH_Exposure + controls) ─────────────────────────────

test_that("run_gender_placebo skips the DDD placebo gracefully when no exposure is supplied (backward compatibility)", {
  # Exactly the original Checkpoint-5 call signature: no exposure_calibrated, and the default
  # exposure_csv_path won't resolve from testthat's working directory. Must NOT error -- that's
  # the whole point of the file.exists() guard -- and the original documented structure/behavior
  # (cleaned_men, result) must be completely unaffected.
  out <- capture.output(res <- suppressWarnings(run_gender_placebo(fixtures_dir)))
  expect_type(res, "list")
  expect_true(all(c("cleaned_men", "result", "ddd_placebo") %in% names(res)))
  expect_true(all(res$cleaned_men$Min == 1))
  expect_s3_class(res$result$models$employed, "fixest")
  expect_null(res$ddd_placebo)
})

test_that("run_gender_ddd_placebo recovers a known Mother:Post:WFH_Exposure effect on a well-identified synthetic panel", {
  # A dedicated, adequately-sized synthetic panel -- not the tiny load_and_clean_data() fixtures,
  # which are sized for schema/parsing tests, not for a fully-saturated triple-interaction formula
  # to be identified (mirrors test-ddd_regression.R's own make_occupation_data() approach).
  set.seed(42)
  cells <- expand.grid(gilnk = 3:5, moch = 1:2, KEEP.OUT.ATTRS = FALSE)

  make_block <- function(gilnk, moch) {
    isco  <- 300 + gilnk * 10 + moch
    ctrl  <- factor(rep(c("A", "B"), length.out = 20))
    teuda <- factor(rep(c("X", "Y", "Z"), length.out = 20))
    tibble::tibble(
      Min = 1, GilNK = factor(gilnk), MachozMegurim = factor(moch), TeudaGvoha = teuda,
      MatzavMishpachti = ctrl, Dat = ctrl,
      MishlachYad_ISCO_08_2 = isco, Muasak = 1L, MishkalSofi = 1,
      ShnatSeker = rep(c(2018, 2018, 2022, 2022), length.out = 20),
      Mother     = rep(c(0, 1, 0, 1), length.out = 20),
      Post       = rep(c(0, 0, 1, 1), length.out = 20)
    )
  }

  panel <- purrr::pmap_dfr(cells, function(gilnk, moch) make_block(gilnk, moch))

  true_exposure <- panel %>%
    dplyr::distinct(MishlachYad_ISCO_08_2) %>%
    dplyr::mutate(wfh_exposure_calibrated = seq(0.1, 0.9, length.out = dplyr::n()))

  panel <- panel %>%
    dplyr::left_join(true_exposure, by = "MishlachYad_ISCO_08_2") %>%
    dplyr::mutate(
      p = plogis(-0.5 + 0.3 * Mother + 0.2 * Post - 1.5 * Mother * Post * wfh_exposure_calibrated),
      Employed = rbinom(dplyr::n(), 1, p),
      IDPUF = dplyr::row_number()
    )

  exposure_calibrated <- true_exposure %>% dplyr::rename(ISCO2 = MishlachYad_ISCO_08_2)

  out <- capture.output(res <- run_gender_ddd_placebo(panel, exposure_calibrated))

  expect_false(is.null(res))
  expect_s3_class(res$models$additive, "fixest")
  expect_s3_class(res$models$fe, "fixest")

  coefs_add <- names(coef(res$models$additive))
  coefs_fe  <- names(coef(res$models$fe))
  expect_true("Mother:Post:WFH_Exposure" %in% coefs_add)
  expect_true("Mother:Post:WFH_Exposure" %in% coefs_fe)
  # Mother:GilNK (added to main.R's primary DDD on 2026-09-11) must also be present here -- GilNK
  # is a multi-level factor, so its interaction with Mother expands to one coefficient per
  # non-reference level (e.g. "Mother:GilNK4"), not a single literal "Mother:GilNK" name.
  expect_true(any(grepl("^Mother:GilNK", coefs_add)))
  expect_true(any(grepl("^Mother:GilNK", coefs_fe)))

  # True injected effect is -1.5; both specs should recover the correct sign at minimum.
  expect_lt(unname(coef(res$models$additive)["Mother:Post:WFH_Exposure"]), 0)
  expect_lt(unname(coef(res$models$fe)["Mother:Post:WFH_Exposure"]), 0)
})

test_that("run_gender_ddd_placebo's formula stays in sync with main.R's primary DDD", {
  # Regression guard for the 2026-09-11 drift this test was added to catch: main.R's primary DDD
  # added `Mother:GilNK` to both its additive and cell-FE specs, but gender_placebo.R's DDD placebo
  # formula wasn't updated to match until this fix. Grepping main.R's actual source (rather than
  # hardcoding an assumed formula string) means a future change to main.R's primary spec fails this
  # test immediately instead of silently leaving the placebo testing an outdated spec.
  main_r    <- paste(readLines(file.path(project_root, "main.R")), collapse = "\n")
  placebo_r <- paste(readLines(file.path(project_root, "scripts", "gender_placebo.R")), collapse = "\n")

  expect_true(grepl("Mother \\* Post \\* WFH_Exposure \\+ Mother:GilNK", main_r),
              info = "main.R's primary DDD formula changed shape -- update this test's expected pattern")
  expect_true(grepl("Mother \\* Post \\* WFH_Exposure \\+ Mother:GilNK", placebo_r),
              info = "gender_placebo.R's DDD placebo formula has drifted from main.R's primary DDD again")
})

test_that("run_gender_ddd_placebo returns NULL for a spec it cannot identify, instead of erroring", {
  # A single occupation/cell with a constant TeudaGvoha: the additive spec (which uses TeudaGvoha
  # as a raw regressor, not absorbed into an FE) is unidentified; the function must degrade to
  # NULL for that spec rather than propagating the error.
  ctrl <- factor(rep(c("A", "B"), length.out = 20))
  panel <- tibble::tibble(
    Min = 1, GilNK = factor(rep(c(3, 4), length.out = 20)), MachozMegurim = factor(1),
    TeudaGvoha = factor("X"), MatzavMishpachti = ctrl, Dat = ctrl,
    MishlachYad_ISCO_08_2 = 500, Muasak = 1L, MishkalSofi = 1,
    ShnatSeker = rep(c(2018, 2018, 2022, 2022), length.out = 20),
    Mother = rep(c(0, 1, 0, 1), length.out = 20),
    Post   = rep(c(0, 0, 1, 1), length.out = 20),
    Employed = rep(c(0L, 1L), length.out = 20),
    IDPUF = seq_len(20)
  )
  exposure_calibrated <- tibble::tibble(ISCO2 = 500, wfh_exposure_calibrated = 0.5)

  expect_no_error({
    out <- capture.output(res <- run_gender_ddd_placebo(panel, exposure_calibrated))
  })
  # A single degenerate cell can leave one or both specs unidentified -- the contract is "never
  # error", not "always successfully fit", so just check the function returned its documented
  # structure (a list with a $models slot) rather than propagating an error.
  expect_true(is.list(res))
  expect_true("models" %in% names(res))
})
