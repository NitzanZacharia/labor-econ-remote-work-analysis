#gender_placebo
# Checkpoint 5 (docs/ROADMAP.md): the Gender Placebo Test from the research doc (Part 2 §3 /
# Part 4 §5) -- replicates the primary DiD model on men (fathers vs. childless men) instead of
# women, to test whether the observed effect is specifically a *motherhood* penalty rather than a
# general *parenthood* or macro shift. Reuses basic_reg() as-is: the "Mother" column (1 if any
# children <17) is sex-agnostic in its derivation, so for this male subsample it's conceptually
# read as "Father" without any code/column rename.
library(tidyverse)
library(fixest)
source("data_processing.R")
source("validation.R")
source("basic_regression.R")

run_gender_placebo <- function(folder_path) {
  message("Loading data for men (sex_filter = 'men')...")
  cleaned_men <- load_and_clean_data(folder_path, sex_filter = "men")

  message("Validating cleaned data (male subsample)...")
  validate_cleaned_df(cleaned_men, sex_filter = "men")

  # Human gate (docs/AUTONOMOUS_RUN_PLAN.md Checkpoint 5): report category sizes only -- a
  # category that's sparse for women (e.g. single-father counts in MisparHorimYechidim) may be
  # near-empty for men. Whether a sparse category needs collapsing is a modeling decision for the
  # researchers, not something this function decides unilaterally.
  message("=== Regression control category sizes, male subsample (report only) ===")
  for (col in DEFAULT_CONTROLS) {
    message("--- ", col, " ---")
    print(table(cleaned_men[[col]], useNA = "ifany"))
  }

  message("Running basic_reg() on the male subsample ('Mother' column read as 'has children <17' ",
          "-- i.e. Father, for this population)...")
  result <- basic_reg(cleaned_men)

  invisible(list(
    cleaned_men = cleaned_men,
    result      = result
  ))
}
