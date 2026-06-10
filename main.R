#main

# 1. Clear environment and load modules
rm(list = ls())
source("data_processing.R")
source("basic_regression.R")

folder_path <- "G:/My Drive/Uni/econ/csv_data"


# 2. Execute data pipeline
message("Loading and cleaning data...")
cleaned_df <-load_and_clean_data(folder_path)
dim(clean_df) #remove later !
colnames(clean_df) #remove later !
# 3. Run different regressions
message("Running basic regression model...")
baseline_results <- basic_reg(cleaned_df)

# 4. Export results
summary(baseline_results)
#saveRDS(interaction_results, "interaction_model_output.rds")
message("Pipeline completed successfully!")