#main

# 1. Clear environment and load modules
rm(list = ls())
source("data_processing.R")
source("basic_regression.R")
message("edit folder_path if needed!")
folder_path <- "G:/My Drive/Uni/econ/csv_data"


# 2. Execute data pipeline
message("Loading and cleaning data...")
cleaned_df <-load_and_clean_data(folder_path)
dim(cleaned_df) #remove later !
colnames(cleaned_df) #remove later !
# 3. Run different regressions
message("Running basic regression model...")
baseline_results <- basic_reg(cleaned_df)


# 4. Export results
summary(baseline_results)
# Employment rate by Mother/Post cells — the 2x2 DiD table
cleaned_df %>%
  group_by(Mother, Post) %>%
  summarise(emp_rate = mean(Employed, na.rm = TRUE), n = n())

# If the DiD is picking up something real, you should see:
# emp(Mother=1, Post=1) - emp(Mother=1, Post=0) 
# meaningfully different from
# emp(Mother=0, Post=1) - emp(Mother=0, Post=0)
#saveRDS(interaction_results, "interaction_model_output.rds")
# Replace Post with year dummies — if pre-2021 year coefficients 
# on Mother x Year are jointly zero, parallel trends holds

cleaned_df %>% count(Employed)
cleaned_df <- cleaned_df %>%
  mutate(ShnatSeker = factor(ShnatSeker, levels = c(2019, 2017, 2018, 2021, 2022, 2023)))
# 2019 as base year (last pre-period)

reg_pretrend <- feols(
  Employed ~ Mother + i(ShnatSeker, Mother, ref = 2019) + 
    MatzavMishpachti + Dat + TeudaGvoha + GilNK + MachozMegurim + MisparHorimYechidim,
  data = cleaned_df, cluster = ~IDPUF
)
iplot(reg_pretrend)  # plots interaction coefficients — should be flat pre-2021
message("Pipeline completed successfully!")
