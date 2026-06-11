#main

# 1. Clear environment and load modules
rm(list = ls())
source("data_processing.R")
source("basic_regression.R")
message("edit folder paths if needed!")
folder_path <- "G:/My Drive/Uni/econ/csv_data"
rds_file_path <- paste0(folder_path, "/cleaned_df.rds")

# 2. Execute data pipeline (with caching)
if (file.exists(rds_file_path)) {
  message("Found saved RDS file! Loading pre-cleaned data...")
  cleaned_df <- readRDS(rds_file_path)
  
} else {
  message("Saved RDS not found. Loading and cleaning raw data...")
  cleaned_df <- load_and_clean_data(folder_path)
  
  # Save the cleaned DF so we can skip this next time
  message("Saving cleaned data to Google Drive for future use...")
  saveRDS(cleaned_df, file = rds_file_path)
}
dim(cleaned_df) #remove later !
colnames(cleaned_df) #remove later !
#save cleaned DF instead of recleaning data


# 3. Run different regressions
message("Running basic regression model...")
baseline_results <- basic_reg(cleaned_df)


# 4. Export results
summary(baseline_results)

#מפה והלאה - שטויות ובדיקות - למחוק
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
cleaned_df %>% 
  select(Employed, Mother, Post, MatzavMishpachti, Dat, GilNK, 
         MachozMegurim, TeudaGvoha, MisparHorimYechidim) %>%
  summarise(across(everything(), ~sum(is.na(.))))
# See if NAs are systematically different
cleaned_df %>%
  mutate(emp_missing = is.na(Employed)) %>%
  group_by(emp_missing) %>%
  summarise(
    pct_mother = mean(Mother, na.rm = TRUE),
    mean_age   = mean(GilNK, na.rm = TRUE),
    n          = n()
  )
cleaned_df %>% filter(is.na(Employed)) %>% head(10) %>% print(width = Inf)
cleaned_df %>% 
  filter(is.na(Employed)) %>% 
  select(
    ShnatSeker,
    Oved35Shaot,
    MisraMelea,
    SibaLeAvodaChelkit,
    AvadShanaAchrona,
    KamaChodashimAvadBashana,
    SibaLoAvadHashana,
    ShaotAvodaBederechKlalNK,
    MachozYishuvAvoda,
    Muasak,
    ShaotIkarit,
    AvodaMeHaBayit,
    AvadMeHaBayit,
    KamaShaot,
    Employed
  ) %>% 
  head(20) %>% 
  print(width = Inf)
