# test-schema-drift.R
# Checkpoint 2 (docs/ROADMAP.md): unit tests for check_schema_drift() using two tiny header-only
# fixture folders:
#   - fixtures/schema_check_ok/: two files with the boundary-column ranges laid out identically
#     -> must pass silently.
#   - fixtures/schema_check_drift/: a reference file plus a second file where a column has been
#     moved into the RamatDat:BituachLeumi range (replacing FillerB with SomeKeptColumn) -> must
#     throw a clear error identifying the affected range and files.

test_that("check_schema_drift passes silently when every file's boundary-column ranges match", {
  ok_dir <- file.path(fixtures_dir, "schema_check_ok")
  expect_silent(check_schema_drift(ok_dir))
})

test_that("check_schema_drift throws a clear error when a range's column composition drifts", {
  drift_dir <- file.path(fixtures_dir, "schema_check_drift")
  err <- tryCatch(check_schema_drift(drift_dir), error = function(e) e)
  expect_s3_class(err, "error")
  # the error should name the drifted range and both files involved
  expect_match(conditionMessage(err), "RamatDat:BituachLeumi", fixed = TRUE)
  expect_match(conditionMessage(err), "2019_Data.csv", fixed = TRUE)
  expect_match(conditionMessage(err), "2021_Data.csv", fixed = TRUE)
})

test_that("check_schema_drift stops on a missing folder", {
  expect_error(check_schema_drift(file.path(fixtures_dir, "does_not_exist")), "not found")
})
