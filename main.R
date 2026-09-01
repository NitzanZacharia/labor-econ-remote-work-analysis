# main.R

# ── 1. Clear environment and load modules ─────────────────────────────────────
rm(list = ls())
source("data_processing.R")
source("comparative_statistics.R")
source("basic_regression.R")
source("basic_reg_compared_data.R")
source("Diagnostics.R")
source("employment_by_child_age.R")
source("validation.R")
source("intensive_margin_regression.R")
source("gender_placebo.R")

# ── 2. Configure paths ────────────────────────────────────────────────────────
message("Edit folder paths if needed!")
folder_path   <- "G:/My Drive/Uni/econ/csv_data"
rds_file_path <- paste0(folder_path, "/cleaned_df.rds")

# ── 3. Execute data pipeline (with caching) ───────────────────────────────────
if (file.exists(rds_file_path)) {
  message("Found saved RDS file — loading pre-cleaned data...")
  cleaned_df <- readRDS(rds_file_path)
} else {
  message("Checking raw CSV schema for column-order drift...")
  check_schema_drift(folder_path)
  message("Saved RDS not found — loading and cleaning raw data...")
  cleaned_df <- load_and_clean_data(folder_path)
  message("Saving cleaned data for future use...")
  saveRDS(cleaned_df, file = rds_file_path)
}

message("Validating cleaned data...")
validate_cleaned_df(cleaned_df)

# ── 4. Comparative statistics ─────────────────────────────────────────────────
message("Running comparative statistics...")
comp_stats <- run_comparative_stats(cleaned_df)

# ── 5. Run regressions ────────────────────────────────────────────────────────
message("Running basic regression model...")
baseline_results <- basic_reg(cleaned_df)

message("Running basic regression model — Jewish women only...")
baseline_jewish <- basic_reg(filter(cleaned_df, Leom == 1))

message("Running basic regression model — Arab women only...")
baseline_arab <- basic_reg(filter(cleaned_df, Leom == 2))

message("Running intensive-margin (work hours) regression...")
intensive_results <- run_intensive_margin_reg(cleaned_df)

# ── 6. Run descriptive stats ────────────────────────────────────────────────────────
message("Running employment_by_child_age...")
emp_res <-employment_by_child_age(cleaned_df)
# ── 7. Export results ─────────────────────────────────────────────────────────
summary(baseline_results)

# ── 8. Debug ─────────────────────────────────────────────────────────
run_diagnostics(cleaned_df)
