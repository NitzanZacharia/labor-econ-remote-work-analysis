library(tidyverse)

# 1. טעינת הנתונים המנוקים ישירות מקובץ המטמון (חוסך את כל תהליך הניקוי)
# folder_path/rds_file_path mirror main.R's own caching convention exactly (main.R:31-32) -- this
# previously hardcoded a repo-relative "csvs/cleaned_df.rds" path that didn't match main.R's actual
# external, gitignored cache location, so this script was broken for anyone using main.R as-is.
message("Edit folder path if needed!")
folder_path   <- "G:/My Drive/Uni/econ/csv_data"
rds_file_path <- paste0(folder_path, "/cleaned_df.rds")
if (!file.exists(rds_file_path)) {
  stop("No cached cleaned_df.rds found at ", rds_file_path,
       " -- run main.R first to build the cache, or update folder_path above.")
}
message("Loading pre-cleaned data...")
cleaned_df <- readRDS(rds_file_path)

# 2. טעינה והפעלה של סקריפט הפערים
source(file.path("scripts", "israeli_market_mismatch.R"))
mismatch_table <- check_market_mismatch(cleaned_df)

# 3. שמירת התוצאה
write_csv(mismatch_table, "outputs/israeli_market_mismatch.csv")
message("Mismatch table successfully saved to outputs/israeli_market_mismatch.csv")