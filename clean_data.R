library(tidyverse)
rm(list = ls())
folder_path <- "G:/My Drive/Uni/econ/csv_data"
file_names <- list.files(path = folder_path, pattern = "*.csv", full.names = TRUE)
# 2. קריאה ואיחוד חכם שמתמודד עם מספר עמודות שונה
lfs_data_raw <- file_names %>%
  # שומר את שמות הקבצים כדי שנוכל לזהות את המקור של כל שורה
  set_names() %>% 
  # קורא כל קובץ בנפרד ומחבר אותם, תוך התעלמות מהבדלי העמודות
  map_df(~read_csv(.x, guess_max = 50000, show_col_types = FALSE), .id = "file_source")

# בדיקה שהכל עבד וכמה שורות/עמודות יש עכשיו
dim(lfs_data_raw)
# 2. ניקוי הנתונים ויצירת משתני ליבה
clean_df <- lfs_data_raw %>%
  mutate(
    # איחוד משתנים שהשם שלהם התפצל בין 2017 ל-2018 (באמצעות coalesce)
    SibaAvadPachot_Unified = coalesce(SibaAvadPachot, SibaAvadPachotmechushav),
    KamaPachot_Unified = coalesce(KamaPachot, KamaPachotmechushav),
    
    # הגדרת קבוצת הטיפול (אימהות): 1 אם יש לפחות ילד אחד מתחת לגיל 17, 0 אחרת
    Mother = ifelse(MisparYeladimAd17MB > 0, 1, 0),
    
    # הגדרת תקופת הזמן (Post): 1 לשנות הפוסט-קורונה, 0 לשנים שלפני
    Post = ifelse(ShnatSeker >= 2021, 1, 0),
    
    # הגדרת מועסקת (יש לבדוק בספר הצפנים ש-1 אכן מייצג "מועסק")
    Employed = ifelse(Muasak == 1, 1, 0),
    
    # יצירת משתנה עבודה מרחוק (WFH)
    # משום שהשאלה נוספה רק ב-2020, נקודד אותה רק עבור 2021 ואילך. 
    # עבור שנים קודמות נשאיר את הערך כחסר (NA) כדי שלא יעוות ממוצעים.
    WFH = case_when(
      ShnatSeker >= 2021 & AvodaMeHaBayit == 1 ~ 1,
      ShnatSeker >= 2021 & AvodaMeHaBayit != 1 ~ 0,
      TRUE ~ NA_real_
    )
  ) %>%
  
  # סינון לאוכלוסיית היעד
  filter(
    Min == 2,                                               # נשים בלבד
    # Glink 3 = age group 25-29
    # Glink 7 = age group 55-59 (since 8 is 60-64 and some retire at 62 and some 65)
    GilNK >= 3 & GilNK <= 7,                               
    ShnatSeker %in% c(2017, 2018, 2019, 2021, 2022, 2023)   # השמטת 2020
  ) %>%
  
  # סינון תצפיות שחסר להן סיווג מקצוע (לא ניתן לחשב עבורן את המדד)
  drop_na(MishlachYad_ISCO_08_2)
colnames(clean_df)
