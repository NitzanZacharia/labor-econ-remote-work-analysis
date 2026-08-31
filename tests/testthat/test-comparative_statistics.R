# test-comparative_statistics.R
# Priority 3: run_comparative_stats()'s dplyr pipelines are simpler than Priority 1/2, but still
# worth regression-guarding since these numbers are the kind that go straight into a paper.

cleaned <- load_and_clean_data(fixtures_dir)

test_that("run_comparative_stats returns the documented structure on fixture data", {
  out <- capture.output(res <- run_comparative_stats(cleaned))

  expect_type(res, "list")
  expect_true(all(c("missing_pct", "emp_by_mother", "mobility_by_year", "plots") %in% names(res)))
  expect_s3_class(res$plots$mobility, "ggplot")
})

test_that("Employed shows exactly 0% missing in the missingness table", {
  out <- capture.output(res <- run_comparative_stats(cleaned))
  emp_row <- res$missing_pct[res$missing_pct$variable == "Employed", ]
  expect_equal(nrow(emp_row), 1)
  expect_equal(emp_row$pct_missing, 0)
})

test_that("emp_by_mother's hand-computable employment rate matches a direct calculation", {
  out <- capture.output(res <- run_comparative_stats(cleaned))
  for (m in unique(cleaned$Mother)) {
    expected_rate <- mean(cleaned$Employed[cleaned$Mother == m], na.rm = TRUE)
    actual_rate <- res$emp_by_mother$emp_rate[res$emp_by_mother$Mother == m]
    expect_equal(actual_rate, expected_rate, info = paste("Mother =", m))
  }
})
