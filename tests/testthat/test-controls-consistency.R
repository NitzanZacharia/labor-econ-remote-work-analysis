# test-controls-consistency.R
# The `controls` vector is copy-pasted identically into basic_regression.R,
# basic_reg_compared_data.R, and employment_by_child_age.R (and inlined again in Diagnostics.R's
# feols() formula). This test guards against the three/four copies drifting apart -- exactly the
# kind of duplication that had to be kept in sync by hand across earlier rounds of changes to this
# codebase.

test_that("controls vector is identical across the three files that define it", {
  c1 <- extract_controls_vector(file.path(project_root, "basic_regression.R"))
  c2 <- extract_controls_vector(file.path(project_root, "basic_reg_compared_data.R"))
  c3 <- extract_controls_vector(file.path(project_root, "employment_by_child_age.R"))

  expect_identical(c1, c2)
  expect_identical(c1, c3)
})

test_that("Diagnostics.R's inline event-study formula includes every control from the shared vector", {
  txt <- paste(readLines(file.path(project_root, "Diagnostics.R"), warn = FALSE), collapse = "\n")
  m <- regmatches(txt, regexpr("feols\\([\\s\\S]*?data = df_pt", txt, perl = TRUE))
  expect_length(m, 1)

  controls <- extract_controls_vector(file.path(project_root, "basic_regression.R"))
  for (ctrl in controls) {
    expect_true(grepl(ctrl, m, fixed = TRUE), info = ctrl)
  }
})
