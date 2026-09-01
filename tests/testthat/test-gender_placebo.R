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
  out <- capture.output(res <- run_gender_placebo(fixtures_dir))
  expect_type(res, "list")
  expect_true(all(c("cleaned_men", "result") %in% names(res)))
  expect_true(all(res$cleaned_men$Min == 1))
  expect_s3_class(res$result$models$employed, "fixest")
})
