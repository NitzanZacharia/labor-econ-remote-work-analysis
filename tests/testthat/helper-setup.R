# helper-setup.R
# testthat auto-sources every helper-*.R file (with working directory set to tests/testthat/)
# before running any test-*.R file. This locates the project root robustly (regardless of exactly
# where testthat sets the working directory), sources the 6 function-bearing .R files (never
# main.R itself — it does rm(list=ls()) and would wipe the test session), and exposes shared
# fixtures/helpers used across test files.

find_project_root <- function(start = getwd()) {
  dir <- normalizePath(start, mustWork = TRUE)
  for (i in 1:8) {
    if (file.exists(file.path(dir, "main.R"))) return(dir)
    parent <- dirname(dir)
    if (parent == dir) break
    dir <- parent
  }
  stop("Could not locate project root (main.R not found in any parent of ", start, ")")
}

project_root <- find_project_root()

# The 19 function-bearing files live in scripts/ and each other's internal source() calls (e.g.
# data_processing.R referenced from basic_regression.R) use root-relative paths like
# file.path("scripts", "data_processing.R") -- resolved against the current working directory, not
# against the sourced file's own location. So instead of chdir=TRUE per file (which would cd into
# scripts/ and break those internal file.path("scripts", ...) calls by doubling the prefix), pin the
# working directory to project_root once for the whole block and restore it explicitly afterward.
# (Not on.exit(): at this top-level script scope there's no enclosing function frame to attach a
# reliable exit handler to, so an explicit setwd() back is used instead.)
old_wd <- setwd(project_root)

source(file.path("scripts", "data_processing.R"))
source(file.path("scripts", "comparative_statistics.R"))
source(file.path("scripts", "basic_regression.R"))
source(file.path("scripts", "basic_reg_compared_data.R"))
source(file.path("scripts", "intensive_margin_regression.R"))
source(file.path("scripts", "imbens_manski_ci.R"))
source(file.path("scripts", "intensive_margin_lee_bounds.R"))
source(file.path("scripts", "gender_placebo.R"))
source(file.path("scripts", "wfh_exposure_index.R"))
source(file.path("scripts", "wfh_exposure_cells.R"))
source(file.path("scripts", "isco_masking_diagnostics.R"))
source(file.path("scripts", "ddd_collinearity_diagnostics.R"))
source(file.path("scripts", "israeli_market_mismatch.R"))
source(file.path("scripts", "ddd_regression.R"))
source(file.path("scripts", "hours_ddd_regression.R"))
source(file.path("scripts", "hours_ddd_lee_bounds.R"))
source(file.path("scripts", "wfh_first_stage_check.R"))
source(file.path("scripts", "ddd_mde_diagnostics.R"))
source(file.path("scripts", "export_results.R"))
source(file.path("scripts", "Diagnostics.R"))
source(file.path("scripts", "employment_by_child_age.R"))
source(file.path("scripts", "validation.R"))

# The 4 robustness-chain scripts below live in robustness/, not scripts/ -- each defines several
# related functions (a diagnostic + one or more regression specs sharing it), not the single
# function per file convention scripts/ holds its 17 members to.
source(file.path("robustness", "balance_test.R"))
source(file.path("robustness", "age_balance_robustness.R"))
source(file.path("robustness", "phase2_robustness.R"))
source(file.path("robustness", "pretrend_wald_test.R"))

setwd(old_wd)

fixtures_dir <- file.path(project_root, "tests", "testthat", "fixtures")

# Redirects graphics output to a null device for the duration of `expr`, so Diagnostics.R's
# dev.new()/iplot() calls neither pop a window nor litter the repo with stray PDFs when tests run
# headlessly. Base-R only (no withr dependency).
with_null_device <- function(expr) {
  grDevices::pdf(file = nullfile())
  on.exit(grDevices::dev.off(), add = TRUE)
  force(expr)
}

# Extracts the value assigned to `controls` in a source file's text -- either a `c(...)`
# character-vector literal, or (since Checkpoint 3) a bare reference like `DEFAULT_CONTROLS`.
# Relies on the controls assignment containing no nested parentheses in the c(...) case, which
# holds for how it's written in this codebase today.
extract_controls_vector <- function(file_path) {
  txt <- paste(readLines(file_path, warn = FALSE), collapse = "\n")
  m <- regmatches(txt, regexpr("controls\\s*<-\\s*(c\\([^)]*\\)|[A-Za-z_][A-Za-z0-9_.]*)", txt))
  if (length(m) != 1 || !nzchar(m)) {
    stop("Could not find a `controls <- ...` assignment in ", file_path)
  }
  eval(parse(text = m), envir = globalenv())
}
