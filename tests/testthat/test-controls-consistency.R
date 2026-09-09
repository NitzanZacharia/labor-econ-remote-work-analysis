# test-controls-consistency.R
# Since Checkpoint 3, basic_regression.R, basic_reg_compared_data.R, employment_by_child_age.R,
# Diagnostics.R, and validation.R all reference the single DEFAULT_CONTROLS constant defined in
# data_processing.R, rather than each defining (or inlining) their own copy. This test guards
# against a future edit reintroducing a local copy in any of them -- exactly the kind of
# duplication that had to be kept in sync by hand across earlier rounds of changes to this
# codebase, before Checkpoint 3. validation.R was itself a live violation of this rule (a
# hardcoded `regression_controls <- c(...)` literal, undetected because this test previously
# didn't scan it) until it was fixed to reference DEFAULT_CONTROLS.

test_that("DEFAULT_CONTROLS has the expected 5 controls, in the documented order", {
  expect_identical(
    DEFAULT_CONTROLS,
    c("MatzavMishpachti", "Dat", "GilNK", "MachozMegurim", "TeudaGvoha")
  )
})

test_that("controls vector is identical (== DEFAULT_CONTROLS) across the three files that define it", {
  c1 <- extract_controls_vector(file.path(project_root, "scripts", "basic_regression.R"))
  c2 <- extract_controls_vector(file.path(project_root, "scripts", "basic_reg_compared_data.R"))
  c3 <- extract_controls_vector(file.path(project_root, "scripts", "employment_by_child_age.R"))

  expect_identical(c1, DEFAULT_CONTROLS)
  expect_identical(c2, DEFAULT_CONTROLS)
  expect_identical(c3, DEFAULT_CONTROLS)
})

test_that("no file reintroduces a local `*controls <- c(...)` literal instead of referencing DEFAULT_CONTROLS", {
  # Matches both `controls <- c(...)` (basic_regression.R etc.) and `regression_controls <- c(...)`
  # (validation.R) -- the pattern has no anchor, so it matches the substring "controls <- c(...)"
  # regardless of what precedes "controls" in the variable name.
  for (f in c("basic_regression.R", "basic_reg_compared_data.R", "employment_by_child_age.R",
              "validation.R")) {
    txt <- paste(readLines(file.path(project_root, "scripts", f), warn = FALSE), collapse = "\n")
    expect_false(grepl("controls\\s*<-\\s*c\\(", txt), info = f)
  }
})

test_that("Diagnostics.R's event-study formula is built from DEFAULT_CONTROLS, not a hardcoded list", {
  txt <- paste(readLines(file.path(project_root, "scripts", "Diagnostics.R"), warn = FALSE), collapse = "\n")
  expect_true(grepl("DEFAULT_CONTROLS", txt, fixed = TRUE))
  # and no leftover hardcoded control names inlined directly into the formula string
  expect_false(grepl("MatzavMishpachti \\+ Dat \\+ TeudaGvoha", txt))
})

test_that("validation.R's regression_controls references DEFAULT_CONTROLS, not a local literal", {
  txt <- paste(readLines(file.path(project_root, "scripts", "validation.R"), warn = FALSE), collapse = "\n")
  expect_true(grepl("regression_controls\\s*<-\\s*DEFAULT_CONTROLS", txt))
})
