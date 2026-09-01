library(tidyverse)

# Single source of truth for the regression controls used across basic_regression.R,
# basic_reg_compared_data.R, employment_by_child_age.R, and Diagnostics.R (Checkpoint 3 --
# previously copy-pasted identically into each of those files).
DEFAULT_CONTROLS <- c("MatzavMishpachti", "Dat", "GilNK", "MachozMegurim", "TeudaGvoha")

load_and_clean_data <- function(folder_path, sex_filter = c("women", "men")) {

  sex_filter <- match.arg(sex_filter)
  min_code <- if (sex_filter == "women") 2 else 1

  # ── 1. Load raw data ────────────────────────────────────────────────────────
  if (!dir.exists(folder_path)) stop("Target data folder not found.")

  data_raw <- list.files(folder_path, pattern = "\\.csv$", full.names = TRUE) %>%
    set_names() %>%
    map_df(~read_csv(.x, guess_max = 50000, show_col_types = FALSE), .id = "file_source")

  # ── 2. Filter ────────────────────────────────────────────────────────────────
  # Min == 2 (women) or Min == 1 (men), per sex_filter -- default "women" preserves the original,
  # unconditional Min == 2 behavior for every existing caller (Checkpoint 5: Gender Placebo Test)
  # GilNK 3–7: age groups 25–59
  # ShnatSeker: relevant survey years (excl. 2020)
  filtered_df <- data_raw %>%
    filter(
      Min == min_code,
      between(GilNK, 3, 7),
      ShnatSeker %in% c(2017, 2018, 2019, 2021, 2022, 2023)
    )
  
  # ── 3. Create new variables ──────────────────────────────────────────────────
  # ShaotAvodaBederechKlalNK bin -> median usual weekly hours (codebook: bin bounds)
  hour_bin_median <- c(`0` = 0, `1` = 4, `2` = 11, `3` = 18, `4` = 25.5, `5` = 32,
                        `6` = 37, `7` = 42, `8` = 47, `9` = 54.5, `10` = 78.5)

  mutated_df <- filtered_df %>%
    mutate(
      Mother                 = as.integer(MisparYeladimAd17MB > 0),
      Post                   = as.integer(ShnatSeker >= 2021),
      # Y: not Muasak==1 ("employed") is treated as "not working" (unemployed and
      # not-in-labor-force are not distinguished), per project guidance.
      Employed = if_else(!is.na(Muasak) & Muasak == 1, 1L, 0L),
      WFH = case_when(
        ShnatSeker >= 2021 & AvodaMeHaBayit == 1 ~ 1,
        ShnatSeker >= 2021 & AvodaMeHaBayit != 1 ~ 0,
        .default = NA_real_
      ),
      MishlachYad_ISCO_08_2 = suppressWarnings(as.numeric(MishlachYad_ISCO_08_2)),

      # Continuous work-hours variable: bins 0-10 -> their range's median; codes
      # 11/12 (irregular hours, <35 / >=35) imputed from the sample's own median
      # hours among regular workers in the matching range; code 99 (irregular,
      # unknown extent) -> NA.
      .hour_bin_val = unname(hour_bin_median[as.character(ShaotAvodaBederechKlalNK)]),
      WorkHoursCont = case_when(
        ShaotAvodaBederechKlalNK %in% 0:10 ~ .hour_bin_val,
        ShaotAvodaBederechKlalNK == 11      ~ median(.hour_bin_val[ShaotAvodaBederechKlalNK %in% 1:5], na.rm = TRUE),
        ShaotAvodaBederechKlalNK == 12      ~ median(.hour_bin_val[ShaotAvodaBederechKlalNK %in% 6:10], na.rm = TRUE),
        .default = NA_real_
      ),

      # Education, grouped into broader categories (raw TeudaGvoha codes; 99 -> NA)
      TeudaGvoha = factor(
        case_when(
          TeudaGvoha %in% c(0, 1)    ~ "Below High School",
          TeudaGvoha == 2            ~ "High School (no matriculation)",
          TeudaGvoha == 3            ~ "Matriculation (Bagrut)",
          TeudaGvoha == 4            ~ "Post-secondary, non-academic",
          TeudaGvoha %in% c(5, 6, 7) ~ "Academic Degree (BA/MA/PhD)",
          TeudaGvoha %in% c(8, 9)    ~ "Other/No Certificate",
          .default = NA_character_
        ),
        levels = c("Below High School", "High School (no matriculation)",
                   "Matriculation (Bagrut)", "Post-secondary, non-academic",
                   "Academic Degree (BA/MA/PhD)", "Other/No Certificate")
      ),

      # Country of birth, grouped by continent (raw SemelEretzLeda codes).
      # Israel kept separate (dominant reference group, not a foreign continent);
      # code 7 spans multiple continents in CBS's own coding -> "Other";
      # code 16 is ambiguously double-labeled "unknown"/"other" in the codebook -> NA.
      BirthContinent = factor(case_when(
        SemelEretzLeda == 10                     ~ "Israel",
        SemelEretzLeda %in% c(1, 6, 11, 14)      ~ "Asia",
        SemelEretzLeda %in% c(2, 8, 12, 15)      ~ "Africa",
        SemelEretzLeda %in% c(3, 4, 5, 13)       ~ "Europe",
        SemelEretzLeda == 9                      ~ "North America",
        SemelEretzLeda == 7                      ~ "Other",
        .default = NA_character_
      )),

      # Work mobility: does she commute outside her locality of residence?
      # (DargatNayadut: 0=didn't work, 1=works in residence locality,
      #  2-7=commutes out (increasing distance), 8=unknown)
      WorksOutsideLocality = case_when(
        DargatNayadut == 1          ~ 0L,
        DargatNayadut %in% 2:7      ~ 1L,
        .default = NA_integer_
      )
    ) %>%
    select(-.hour_bin_val) %>%
    mutate(
      across(
        c(MatzavMishpachti, Dat, GilNK, MachozMegurim, MisparHorimYechidim),
        as.factor
      )
    )

  
  # ── 4. Drop unwanted columns ─────────────────────────────────────────────────
  cols_to_drop <- c(
    "ShnotLimud", "SugBeitSeferAcharon", "AvadBeshavua2", "ChipesChodesh",
    "KamaPachot", "SibaAvadPachot", "MisparShaotNosafot", "ShaotAvodaLeMaase",
    "ChozerLamasik", "KamaShavuotChipes", "ChipusAvodaMelea",
    "ZminutLeAvodaMechapsim", "SibatEyZminut", "AvadEyPaamBaaretz",
    "SibaHifsikLaavod", "MatayHifsikLaavod", "ChipesBeShanaAchrona",
    "SibaLoChipesAvoda", "ZminutLeAvodaMityaashim", "MimiMekabelSachar",
    "YeladimAd14PratNK", "GilYeledTzairPratNK", "ShaotAvodaLemaaseNK",
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
    "(",
    paste(c(
      "Kolel", "MisparMugbalim", "Yeshiva", "ChodeshSeker", "ShnatMidgam",
      "ChodeshMidgam", "MisparNefashotMB", "MisparNefashotNosafot",
      "YeladimAd14MBNK", "MisparNefashotMi15MB", "MisparBiltiMuasakim",
      "MisparMuasakimMale", "TtchunatAvoda", "Limudim",
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

