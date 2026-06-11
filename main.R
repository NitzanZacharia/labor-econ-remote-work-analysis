# main.R

# ── 1. Clear environment and load modules ─────────────────────────────────────
rm(list = ls())
source("data_processing.R")
source("basic_regression.R")
source("basic_reg_compared_data.R")
source("diagnostics.R")

# ── 2. Configure paths ────────────────────────────────────────────────────────
message("Edit folder paths if needed!")
folder_path   <- "G:/My Drive/Uni/econ/csv_data"
rds_file_path <- paste0(folder_path, "/cleaned_df.rds")

# ── 3. Execute data pipeline (with caching) ───────────────────────────────────
if (file.exists(rds_file_path)) {
  message("Found saved RDS file — loading pre-cleaned data...")
  cleaned_df <- readRDS(rds_file_path)
} else {
  message("Saved RDS not found — loading and cleaning raw data...")
  cleaned_df <- load_and_clean_data(folder_path)
  message("Saving cleaned data for future use...")
  saveRDS(cleaned_df, file = rds_file_path)
}

# ── 4. Run regressions ────────────────────────────────────────────────────────
message("Running basic regression model...")
baseline_results <- basic_reg(cleaned_df)
comp_res <- basic_reg_comp(cleaned_df) #debug only
# ── 5. Export results ─────────────────────────────────────────────────────────
summary(baseline_results)

# ── 6. Debug ─────────────────────────────────────────────────────────
run_diagnostics(cleaned_df)