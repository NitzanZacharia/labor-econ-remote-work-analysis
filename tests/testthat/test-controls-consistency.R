# test-controls-consistency.R
# Since Checkpoint 3, basic_regression.R, basic_reg_compared_data.R, employment_by_child_age.R,
# and Diagnostics.R all reference the single DEFAULT_CONTROLS constant defined in
# data_processing.R, rather than each defining (or inlining) their own copy. This test guards
# against a future edit reintroducing a local copy in any of them -- exactly the kind of
# duplication that had to be kept in sync by hand across earlier rounds of changes to this
# codebase, before Checkpoint 3.

test_that("DEFAULT_CONTROLS has the expected 5 controls, in the documented order", {
  expect_identical(
    DEFAULT_CONTROLS,
    c("MatzavMishpachti", "Dat", "GilNK", "MachozMegurim", "TeudaGvoha")
  )
})

test_that("controls vector is identical (== DEFAULT_CONTROLS) across the three files that define it", {
  c1 <- extract_controls_vector(file.path(project_root, "basic_regression.R"))
  c2 <- extract_controls_vector(file.path(project_root, "basic_reg_compared_data.R"))
  c3 <- extract_controls_vector(file.path(project_root, "employment_by_child_age.R"))

  expect_identical(c1, DEFAULT_CONTROLS)
  expect_identical(c2, DEFAULT_CONTROLS)
  expect_identical(c3, DEFAULT_CONTROLS)
})

test_that("no file reintroduces a local `controls <- c(...)` literal instead of referencing DEFAULT_CONTROLS", {
  for (f in c("basic_regression.R", "basic_reg_compared_data.R", "employment_by_child_age.R")) {
    txt <- paste(readLines(file.path(project_root, f), warn = FALSE), collapse = "\n")
    expect_false(grepl("controls\\s*<-\\s*c\\(", txt), info = f)
  }
})

test_that("Diagnostics.R's event-study formula is built from DEFAULT_CONTROLS, not a hardcoded list", {
  txt <- paste(readLines(file.path(project_root, "Diagnostics.R"), warn = FALSE), collapse = "\n")
  expect_true(grepl("DEFAULT_CONTROLS", txt, fixed = TRUE))
  # and no leftover hardcoded control names inlined directly into the formula string
  expect_false(grepl("MatzavMishpachti \\+ Dat \\+ TeudaGvoha", txt))
})
