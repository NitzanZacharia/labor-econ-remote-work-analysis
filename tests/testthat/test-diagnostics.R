# test-diagnostics.R
# Priority 2: the event-study releveling (factor(ShnatSeker, levels=c(2019, ...)), ref=2019) is a
# classic silent-failure spot -- get the reference year wrong and every coefficient shifts meaning
# without an error. Graphics calls are redirected to a null device (see helper-setup.R) so this
# runs headlessly without popping a window or writing a stray PDF.

cleaned <- load_and_clean_data(fixtures_dir)

test_that("run_diagnostics returns the documented structure without error on fixture data", {
  with_null_device({
    out <- capture.output(res <- run_diagnostics(cleaned))
  })

  expect_type(res, "list")
  expect_true(all(c("did_table", "na_summary", "miss_pattern", "pretrend_model") %in% names(res)))
  expect_s3_class(res$pretrend_model, "fixest")
})

test_that("2019 is the omitted reference year in the event-study model", {
  with_null_device({
    out <- capture.output(res <- run_diagnostics(cleaned))
  })
  coefs <- names(coef(res$pretrend_model))
  # ref=2019 means no ShnatSeker::2019 interaction term should appear among the coefficients
  expect_false(any(grepl("2019", coefs)))
})

test_that("2x2 DiD table covers both Mother and Post values present in the fixtures", {
  with_null_device({
    out <- capture.output(res <- run_diagnostics(cleaned))
  })
  expect_true(all(c(0, 1) %in% res$did_table$Mother))
  expect_true(all(c(0, 1) %in% res$did_table$Post))
})
