# test-export_results.R
# Checkpoint 9: unit tests for export_all_results() using synthetic fixest/ggplot objects,
# confirming file creation and naming -- not real content (that's Lane B, against real data).
# All output goes to a temp directory, cleaned up after each test, so these tests never touch the
# repo's own outputs/ directory.

make_synth_results <- function() {
  df <- data.frame(y = c(0, 1, 0, 1, 1, 0, 1, 0), x = c(1, 2, 1, 2, 1, 2, 1, 2))
  m <- suppressWarnings(fixest::feols(y ~ x, data = df))
  tb <- fixest::etable(m)

  p <- ggplot2::ggplot(data.frame(a = 1:3, b = 1:3), ggplot2::aes(a, b)) + ggplot2::geom_point()

  list(
    basic_reg = list(
      table  = tb,
      models = list(employed = m)   # a raw fixest object -- must be skipped, not exported
    ),
    comparative_stats = list(
      missing_pct = data.frame(variable = c("a", "b"), pct_missing = c(0, 5)),
      plots       = list(mobility = p)
    )
  )
}

test_that("export_all_results creates the output directory if missing", {
  out_dir <- file.path(tempdir(), paste0("cp9-", as.integer(Sys.time())))
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)
  expect_false(dir.exists(out_dir))

  export_all_results(make_synth_results(), output_dir = out_dir)
  expect_true(dir.exists(out_dir))
})

test_that("export_all_results writes one CSV per data frame and one PNG per ggplot, correctly named", {
  out_dir <- file.path(tempdir(), paste0("cp9-", as.integer(Sys.time()), "-b"))
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

  exported <- export_all_results(make_synth_results(), output_dir = out_dir)
  files <- basename(exported)

  expect_true("basic_reg_table.csv" %in% files)
  expect_true("comparative_stats_missing_pct.csv" %in% files)
  expect_true("comparative_stats_plots_mobility.png" %in% files)
  for (f in exported) expect_true(file.exists(f), info = f)
})

test_that("export_all_results skips raw fixest/lm model objects (no spurious file)", {
  out_dir <- file.path(tempdir(), paste0("cp9-", as.integer(Sys.time()), "-c"))
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

  exported <- export_all_results(make_synth_results(), output_dir = out_dir)
  files <- basename(exported)

  expect_false(any(grepl("models_employed", files)))
  # exactly 3 files: the table CSV, the missing_pct CSV, and the plot PNG -- no 4th from the model
  expect_length(exported, 3)
})

test_that("exported CSV content matches the source data frame", {
  out_dir <- file.path(tempdir(), paste0("cp9-", as.integer(Sys.time()), "-d"))
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

  results <- make_synth_results()
  export_all_results(results, output_dir = out_dir)

  roundtrip <- read.csv(file.path(out_dir, "comparative_stats_missing_pct.csv"))
  expect_equal(roundtrip$variable, results$comparative_stats$missing_pct$variable)
  expect_equal(roundtrip$pct_missing, results$comparative_stats$missing_pct$pct_missing)
})
