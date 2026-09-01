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

# chdir = TRUE: basic_regression.R and basic_reg_compared_data.R each contain their own
# source("data_processing.R") with a path relative to the project root, not to wherever testthat
# happens to set the working directory. chdir=TRUE makes `source()` temporarily cd into each
# file's own directory (the project root) while sourcing it, so those internal relative-path
# source() calls resolve correctly regardless of the caller's working directory.
source(file.path(project_root, "data_processing.R"), chdir = TRUE)
source(file.path(project_root, "comparative_statistics.R"), chdir = TRUE)
source(file.path(project_root, "basic_regression.R"), chdir = TRUE)
source(file.path(project_root, "basic_reg_compared_data.R"), chdir = TRUE)
source(file.path(project_root, "intensive_margin_regression.R"), chdir = TRUE)
source(file.path(project_root, "gender_placebo.R"), chdir = TRUE)
source(file.path(project_root, "Diagnostics.R"), chdir = TRUE)
source(file.path(project_root, "employment_by_child_age.R"), chdir = TRUE)
source(file.path(project_root, "validation.R"), chdir = TRUE)

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
