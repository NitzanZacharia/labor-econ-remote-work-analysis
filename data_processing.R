library(tidyverse)

load_and_clean_data <- function(folder_path) {
  
  # ── 1. Load raw data ────────────────────────────────────────────────────────
  if (!dir.exists(folder_path)) stop("Target data folder not found.")
  
  data_raw <- list.files(folder_path, pattern = "\\.csv$", full.names = TRUE) %>%
    set_names() %>%
    map_df(~read_csv(.x, guess_max = 50000, show_col_types = FALSE), .id = "file_source")
  
  # ── 2. Filter ────────────────────────────────────────────────────────────────
  # Min == 2: women only
  # GilNK 3–7: age groups 25–59
  # ShnatSeker: relevant survey years (excl. 2020)
  filtered_df <- data_raw %>%
    filter(
      Min == 2,
      between(GilNK, 3, 7),
      ShnatSeker %in% c(2017, 2018, 2019, 2021, 2022, 2023)
    )
  
  # ── 3. Create new variables ──────────────────────────────────────────────────
  mutated_df <- filtered_df %>%
    mutate(
      SibaAvadPachot_Unified = coalesce(SibaAvadPachot, SibaAvadPachotmechushav),
      Mother                 = as.integer(MisparYeladimAd17MB > 0),
      Post                   = as.integer(ShnatSeker >= 2021),
      Employed               = as.integer(Muasak == 1),
      WFH = case_when(
        ShnatSeker >= 2021 & AvodaMeHaBayit == 1 ~ 1,
        ShnatSeker >= 2021 & AvodaMeHaBayit != 1 ~ 0,
        .default = NA_real_
      ),
      MishlachYad_ISCO_08_2 = suppressWarnings(as.numeric(MishlachYad_ISCO_08_2))
    ) %>%
    drop_na(MishlachYad_ISCO_08_2)
  
  # ── 4. Drop unwanted columns ─────────────────────────────────────────────────
  cols_to_drop <- c(
    "ShnotLimud", "SugBeitSeferAcharon", "AvadBeshavua2", "ChipesChodesh",
    "KamaPachot", "SibaAvadPachot", "MisparShaotNosafot", "ShaotAvodaLeMaase",
    "ChozerLamasik", "KamaShavuotChipes", "ChipusAvodaMelea",
    "ZminutLeAvodaMechapsim", "SibatEyZminut", "AvadEyPaamBaaretz",
    "SibaHifsikLaavod", "MatayHifsikLaavod", "ChipesBeShanaAchrona",
    "SibaLoChipesAvoda", "ZminutLeAvodaMityaashim", "MimiMekabelSachar",
    "Leom", "YeladimAd14PratNK", "GilYeledTzairPratNK", "ShaotAvodaLemaaseNK",
    "MeshechChipusAvodaNK", "ShnotLimudNK", "ShayachAvoda",
    "SibaAvadPachot10CHodashim", "LimudimVeAvoda", "MityaashimMechipusAvoda",
    "RamatHaskala_ISCED97", "RamatHaskala_ISCED2011", "ShaotOzeretMBMeubad",
    "Pratmugbalkashe", "ShnotLimudLeloYeshivotG", "KamaPachotmechushav",
    "SibaAvadPachotmechushav", "AvadEyPaam", "MimiMekabelSacharMechushav",
    "AavadIkarit", "AvodaAcheret", "BeeluShaot", "BeizoDerech", "Chaverim",
    "ChipesAvodaAcheret", "ChipesShavuot", "ChipesShavuotMityaesh",
    "ChipusAvodaDmeyAvtala", "ChipusAvodaMismachim", "ChipusAvodaShnatHafsaka",
    "ChipusAvodaYachalLehatchil30", "ChipusMeleaMityaesh", "ChipusShaot",
    "ChodeshHafsaka", "ChodeshHafsakaMityaesh", "ChodeshHatchala",
    "DmeyAvtalaMityaesh", "Esek", "HaskalaMatima", "HavtachatHachnasaMityaesh",
    "HifsikMigbala", "HifsikMigbalaMityaesh", "KamaAvodot", "KoachAdam",
    "LehachlifAvoda", "Lehatchil60", "LoChipesMigbala", "ShnatHafsakaMityaesh",
    "SibaHifsikLaavodMityaesh", "SofShavua", "SugMachala", "SugTeuna",
    "YachalLehatchil30Mityaesh", "YamimBashavua", "ZmanLaavoda",
    "KamaPachot_Unified"
  )
  
  # Regex pattern matching any column that starts with these prefixes
  prefix_pattern <- paste0(
    "^(",
    paste(c(
      "Kolel", "MisparMugbalim", "Yeshiva", "ChodeshSeker", "ShnatMidgam",
      "ChodeshMidgam", "MisparNefashotMB", "MisparNefashotNosafot",
      "YeladimAd14MBNK", "MisparNefashotMi15MB", "MisparBiltiMuasakim",
      "MisparMuasakimMale", "SemelEretzLeda", "TtchunatAvoda", "Limudim",
      "MisparChadarimMB", "TzfifutDiyur", "ShayachimKoachAvoda", "YabeshetLeida",
      "VetekNisuinNK", "MaduaLehachlif", "SherutTaasuka", "IsukLifneyShechipes",
      "Needar", "Aliya", "Imut"
    ), collapse = "|"),
    ")"
  )
  
  df <- mutated_df %>%
    select(
      -any_of(cols_to_drop),
      -matches(prefix_pattern),
      -(Yeladim0_1Prat:Yeladim15_17Prat),
      -(MisparHachlafa:YachasKirvaNK),
      -(MisparNefashotGilAvodaV2007:MisparPrat),
      -(ChipusAvodaSherutTaasuka:ChipusAvodaOfenAcher),
      -(EizeChozemechushav:ChodeshKodemShaa),
      -(MimaHaMigbala:PniyaLmaasik),
      -(RamatDat:BituachLeumi)
    )
  
  return(df)
}
#"main" 
folder_path <- "G:/My Drive/Uni/econ/csv_data"
cleaned_data <-load_and_clean_data(folder_path)
dim(clean_df)
colnames(clean_df)
