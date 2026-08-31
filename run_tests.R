# run_tests.R
# One-command entry point for the test suite. Run from the repo root: Rscript run_tests.R
# Exits with status 0 if every test passed, non-zero otherwise (so this composes with CI/scripts
# that check the exit code, per docs/AUTONOMOUS_RUN_PLAN.md's per-checkpoint gate).
library(testthat)

# Several functions under test (run_comparative_stats(), employment_by_child_age(),
# run_diagnostics()) print ggplot/base-graphics output as a side effect, and Diagnostics.R calls
# dev.new() directly. dev.new() always opens a brand-new device regardless of what's already
# open, and on a headless Rscript session with no display it falls back to pdf(file="Rplots.pdf")
# (auto-incrementing on each call), littering the repo. Overriding the *default device
# constructor* (rather than just pre-opening one) is what actually intercepts dev.new()'s own
# fallback and routes it to null for the whole test run.
options(device = function(...) grDevices::pdf(file = base::nullfile()))

results <- test_dir("tests/testthat", reporter = "summary", stop_on_failure = FALSE)

results_df <- as.data.frame(results)
n_fail <- sum(results_df$failed) + sum(results_df$error)

if (!interactive()) {
  quit(status = if (n_fail > 0) 1L else 0L)
}
