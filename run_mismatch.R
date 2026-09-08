library(tidyverse)

# 1. טעינת הנתונים המנוקים ישירות מקובץ המטמון (חוסך את כל תהליך הניקוי)
message("Loading pre-cleaned data...")
cleaned_df <- readRDS("csvs/cleaned_df.rds")

# 2. טעינה והפעלה של סקריפט הפערים
source("israeli_market_mismatch.R")
mismatch_table <- check_market_mismatch(cleaned_df)

# 3. שמירת התוצאה
write_csv(mismatch_table, "outputs/israeli_market_mismatch.csv")
message("Mismatch table successfully saved to outputs/israeli_market_mismatch.csv")