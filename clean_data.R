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
    SibaAvadPachot_Unified = coalesce(SibaAvadPachot, SibaAvadPachotmechushav),
    KamaPachot_Unified = coalesce(KamaPachot, KamaPachotmechushav),
    Mother = ifelse(MisparYeladimAd17MB > 0, 1, 0),
    Post = ifelse(ShnatSeker >= 2021, 1, 0),
    Employed = ifelse(Muasak == 1, 1, 0),
    WFH = case_when(
      ShnatSeker >= 2021 & AvodaMeHaBayit == 1 ~ 1,
      ShnatSeker >= 2021 & AvodaMeHaBayit != 1 ~ 0,
      TRUE ~ NA_real_
    )
  ) %>%
  

  
  filter(
    Min == 2,                                               
    # Glink 3 = age group 25-29
    # Glink 7 = age group 55-59 (since 8 is 60-64 and some retire at 62 and some 65)
    GilNK >= 3 & GilNK <= 7,                                
    ShnatSeker %in% c(2017, 2018, 2019, 2021, 2022, 2023)   
  ) %>%
  
  # 1. ממירים למספרים (משתיקים את האזהרה כי אנחנו יודעים שייווצרו NAs מהערכים הבעייתיים)
  mutate(MishlachYad_ISCO_08_2 = suppressWarnings(as.numeric(MishlachYad_ISCO_08_2))) %>%
  
  # 2. זורקים את כל השורות שקיבלו NA (כולל אלו שהיו "XX" או "..")
  drop_na(MishlachYad_ISCO_08_2) %>%
  #maybe leave the above row for the basic regression???
  # הורדת העמודות הלא רלוונטיות
  select(
    -starts_with("Kolel"),     
    -contains("MisparMugbalim"),
    -contains("Yeshiva")         
  )
clean_df <- clean_df %>%
  select(
    -(MisparHachlafa:YachasKirvaNK),
    -(MisparNefashotGilAvodaV2007:MisparPrat),
    -(ChipusAvodaSherutTaasuka:ChipusAvodaOfenAcher),
    -(EizeChozemechushav:ChodeshKodemShaa),
    -(MimaHaMigbala:PniyaLmaasik),
    -(RamatDat:BituachLeumi),
    -contains("MisparChadarimMB"),
    -contains("TzfifutDiyur"),
    -contains("ShayachimKoachAvoda"),
    -contains("YabeshetLeida"),
    -contains("VetekNisuinNK"),
    -contains("MaduaLehachlif"),
    -contains("SherutTaasuka"),
  )
clean_df <- clean_df %>%
  select(
    -contains("IsukLifneyShechipes"),
    -contains("Needar"),
    -contains("Aliya"),
    -contains("Imut")
  )
#----------
clean_df <- clean_df %>%
  select(
    -(Yeladim0_1Prat:Yeladim15_17Prat)
  )
clean_df <- clean_df %>%
  select(
    -contains("ChodeshSeker"),
    -contains("ShnatMidgam"),
    -contains("ChodeshMidgam"),
    -contains("MisparNefashotMB"),
    -contains("MisparNefashotNosafot"),
    -contains("YeladimAd14MBNK"),
    -contains("MisparNefashotMi15MB"),
    -contains("MisparBiltiMuasakim"),
    -contains("MisparMuasakimMale"),
    -contains("SemelEretzLeda"),
    -contains("TtchunatAvoda"),
    -c(Limudim, ShnotLimud, SugBeitSeferAcharon, AvadBeshavua2, ChipesChodesh, KamaPachot, SibaAvadPachot)
    -c(MisparShaotNosafot, ShaotAvodaLeMaase, ChozerLamasik, KamaShavuotChipes, ChipusAvodaMelea, ZminutLeAvodaMechapsim)
    -c(SibatEyZminut, AvadEyPaamBaaretz, SibaHifsikLaavod, MatayHifsikLaavod, ChipesBeShanaAchrona, SibaLoChipesAvoda, ZminutLeAvodaMityaashim, MimiMekabelSachar)
    -c(Leom, YeladimAd14PratNK, GilYeledTzairPratNK, ShaotAvodaLemaaseNK, MeshechChipusAvodaNK, ShnotLimudNK)
    -c(ShayachAvoda, SibaAvadPachot10CHodashim, LimudimVeAvoda, MityaashimMechipusAvoda, RamatHaskala_ISCED97, RamatHaskala_ISCED2011, ShaotOzeretMBMeubad)
    -c(Pratmugbalkashe, ShnotLimudLeloYeshivotG, KamaPachotmechushav, SibaAvadPachotmechushav, AvadEyPaam, MimiMekabelSacharMechushav, AavadIkarit)
    -c(AvodaAcheret, BeeluShaot, BeizoDerech, Chaverim, ChipesAvodaAcheret, ChipesShavuot, ChipesShavuotMityaesh, ChipusAvodaDmeyAvtala, ChipusAvodaMismachim)
    -c(ChipusAvodaShnatHafsaka, ChipusAvodaYachalLehatchil30, ChipusMeleaMityaesh, ChipusShaot, ChodeshHafsaka, ChodeshHafsakaMityaesh)
    -c(ChodeshHatchala, DmeyAvtalaMityaesh, Esek, HaskalaMatima, HavtachatHachnasaMityaesh, HifsikMigbala, HifsikMigbalaMityaesh, KamaAvodot, KoachAdam, LehachlifAvoda, Lehatchil60, LoChipesMigbala, ShnatHafsakaMityaesh, SibaHifsikLaavodMityaesh, SofShavua, SugMachala, SugTeuna, YachalLehatchil30Mityaesh)
    -c(YamimBashavua, ZmanLaavoda, KamaPachot_Unified)
    )

#remove all limudin except TeudaGvoha!!!!!!!!!!
dim(clean_df)
colnames(clean_df)
