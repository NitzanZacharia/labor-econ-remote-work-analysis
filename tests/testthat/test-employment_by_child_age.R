# test-employment_by_child_age.R
# Priority 2: the recycled-predictions margins block (map_dfr over ChildAgeBin levels,
# re-leveling a temp copy of the data, predict(), average) is complex enough logic to regress
# silently -- this checks the full function runs and returns the documented structure over all
# 5 child-age bins the fixtures are designed to cover.

cleaned <- load_and_clean_data(fixtures_dir)

test_that("employment_by_child_age returns the documented structure on fixture data", {
  out <- capture.output(res <- employment_by_child_age(cleaned))

  expect_type(res, "list")
  expect_true(all(c("emp_raw", "emp_by_period", "model", "plots") %in% names(res)))
  expect_s3_class(res$model, "fixest")
  expect_true(all(c("raw", "period", "adjusted") %in% names(res$plots)))
  for (p in res$plots) expect_s3_class(p, "ggplot")

  # fixtures are designed to cover all 5 GilYeledTzairMBNK bins (1-5)
  expect_equal(nrow(res$emp_raw), 5)
})

test_that("raw and adjusted employment rates are finite", {
  out <- capture.output(res <- employment_by_child_age(cleaned))
  expect_true(all(is.finite(res$emp_raw$emp_rate)))
})
