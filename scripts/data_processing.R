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

  # Both raw hour items (ShaotAvodaLeMaase, KamaShaot) use values in the 90s as codes
  # ("irregular"/"unknown"), not as hour counts, so only 1-89 is a real duration. as.numeric()
  # first because a year whose file has the column entirely empty is read as logical, not numeric.
  hours_or_na <- function(x) {
    v <- suppressWarnings(as.numeric(x))
    if_else(!is.na(v) & v >= 1 & v <= 89, v, NA_real_)
  }

  mutated_df <- filtered_df %>%
    mutate(
      Mother                 = as.integer(MisparYeladimAd17MB > 0),
      Post                   = as.integer(ShnatSeker >= 2021),
      # Y: not Muasak==1 ("employed") is treated as "not working" (unemployed and
      # not-in-labor-force are not distinguished), per project guidance.
      Employed = if_else(!is.na(Muasak) & Muasak == 1, 1L, 0L),
      # ── WFH block (raw columns AvodaMeHaBayit / AvadMeHaBayit / KamaShaot) ──
      # Asked from 2021 onward only -- the columns exist in the 2018-2023 schema but are empty in
      # 100% of pre-2021 rows, so everything here is NA by design before 2021.
      #
      # CBS codes both yes/no items as 1 = yes, 2 = no, 9 = unknown. 9 must map to NA, NOT to 0:
      # the previous `AvodaMeHaBayit != 1 ~ 0` rule silently recoded 2,920 "unknown" responses in
      # 2021 alone (2.4% of employed) as "does not work from home".
      #
      # WFH ("usual work location", asked of every employed person) is kept as the headline
      # measure for backward compatibility, but WFH_RefWeek is the better-behaved series: WFH's
      # level drifts implausibly across years (15.3% -> 12.7% -> 12.4% among employed women 25-59)
      # while WFH_RefWeek is stable (18.3% -> 19.2% -> 19.3%), and WFH_RefWeek correlates more
      # strongly with the external teleworkability benchmark at ISCO-2 level (0.833 vs 0.796).
      WFH = case_when(
        ShnatSeker < 2021   ~ NA_real_,
        AvodaMeHaBayit == 1 ~ 1,
        AvodaMeHaBayit == 2 ~ 0,
        .default = NA_real_          # code 9 ("unknown") and genuine missingness
      ),
      # Reference-week behaviour. Asked only of the employed who actually worked that week
      # (AvadBeshavua == 1), so the ~10,955 employed-but-absent per year are legitimately NA
      # rather than 0.
      WFH_RefWeek = case_when(
        ShnatSeker < 2021  ~ NA_real_,
        AvadMeHaBayit == 1 ~ 1,
        AvadMeHaBayit == 2 ~ 0,
        .default = NA_real_
      ),
      # Intensity. KamaShaot is asked only of WFH_RefWeek == 1 (verified: its non-empty count
      # equals the AvadMeHaBayit == 1 count exactly), and is hours worked from home in the
      # reference week -- confirmed KamaShaot <= ShaotAvodaLeMaase in 18,619/18,619 cases.
      # Values 90-97 in both hour items are CBS codes ("irregular"/"unknown"), not hour counts:
      # every KamaShaot == 97 is paired with ShaotAvodaLeMaase == 97, so they are excluded.
      .hrs_home  = hours_or_na(KamaShaot),
      .hrs_total = hours_or_na(ShaotAvodaLeMaase),
      WFH_Hours = case_when(
        WFH_RefWeek == 0 ~ 0,
        WFH_RefWeek == 1 ~ .hrs_home,
        .default = NA_real_
      ),
      WFH_Share = case_when(
        WFH_RefWeek == 0                  ~ 0,
        WFH_RefWeek == 1 & .hrs_total > 0 ~ pmin(.hrs_home / .hrs_total, 1),
        .default = NA_real_
      ),
      WFH_Arrangement = factor(
        case_when(
          is.na(WFH_Share) ~ NA_character_,
          WFH_Share == 0   ~ "On-site",
          WFH_Share < 0.9  ~ "Hybrid",
          .default         = "Fully remote"
        ),
        levels = c("On-site", "Hybrid", "Fully remote")
      ),

      # ── ISCO-08 occupation code ────────────────────────────────────────────
      # CBS disclosure-masks this field: alongside real codes it contains "XX", "1X", "7X", ...
      # 9,303 of 123,794 employed 2021 rows (7.5%) are masked across the whole file, though only
      # 2.4% within this project's analysis sample (employed women 25-59) -- masking concentrates
      # in thinly-populated occupation cells. as.numeric() turns all of those into NA, which the
      # exposure-index join then drops without a word, so the mask is now recorded explicitly
      # (ISCO_masked) and the 1-digit major group is recovered where it survives the mask (ISCO1),
      # giving a coarser but usable fallback.
      .isco_chr = as.character(MishlachYad_ISCO_08_2),
      MishlachYad_ISCO_08_2 = suppressWarnings(as.numeric(.isco_chr)),
      ISCO_masked = !is.na(.isco_chr) & is.na(MishlachYad_ISCO_08_2),
      ISCO1 = suppressWarnings(as.numeric(str_sub(.isco_chr, 1, 1))),

      # Bin-index -> median-hours lookup for ShaotAvodaBederechKlalNK's regular-hours codes
      # (0-10). WorkHoursCont itself (including the code-11/12 irregular-hours imputation) is
      # computed further below, after this mutate() and grouped by Post -- see that block for why.
      .hour_bin_val = unname(hour_bin_median[as.character(ShaotAvodaBederechKlalNK)]),

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
    # Continuous work-hours variable: bins 0-10 -> their range's median (a per-row lookup,
    # independent of period). Codes 11/12 (irregular hours, <35 / >=35 weekly) are imputed from
    # the sample's OWN median hours among regular (non-irregular) workers in the matching range --
    # computed separately for the pre- (Post==0) and post- (Post==1) WFH-shift periods, not pooled
    # across 2017-2023. Pooling both periods into one constant would silently blend their hour
    # distributions and mechanically dampen exactly the kind of period-specific intensity shift
    # (irregular-hours workers' typical hours changing after WFH adoption) the intensive-margin
    # DiD (intensive_margin_regression.R) is designed to detect. Code 99 (irregular, unknown
    # extent) -> NA, same as before.
    group_by(Post) %>%
    mutate(
      WorkHoursCont = case_when(
        ShaotAvodaBederechKlalNK %in% 0:10 ~ .hour_bin_val,
        ShaotAvodaBederechKlalNK == 11      ~ median(.hour_bin_val[ShaotAvodaBederechKlalNK %in% 1:5], na.rm = TRUE),
        ShaotAvodaBederechKlalNK == 12      ~ median(.hour_bin_val[ShaotAvodaBederechKlalNK %in% 6:10], na.rm = TRUE),
        .default = NA_real_
      )
    ) %>%
    ungroup() %>%
    select(-.hour_bin_val, -.hrs_home, -.hrs_total, -.isco_chr) %>%
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
    "KamaPachot_Unified",
    # Formerly dropped via 2 positional ranges (-(EizeChozemechushav:ChodeshKodemShaa) and
    # -(MimaHaMigbala:PniyaLmaasik)); moved to explicit any_of()-based names because
    # 2017_Data.csv lacks all 4 boundary columns entirely (confirmed: 2018-2023 have them
    # consistently), which made the positional-range approach fail check_schema_drift() on a
    # file that was never going to contain the columns in the first place. any_of() tolerates
    # a name simply not existing in a given year, unlike a positional a:b range. No columns
    # dropped here are used anywhere downstream (verified via grep before this change).
    "EizeChozemechushav", "HaimMemunemechushav", "HaimMenahelmechushav",
    "KamaKfufimmechushav", "KamaSchirimmechushav", "LoAvadMigbalamechushav",
    "MaasikSchirimmechushav", "MeshechChipusAvodaMityaeshNK", "MeshechChipusAvodaMuasakNK",
    "MigzarKalkalimechushav", "SacharMechushavmechushav", "SemelMikzoamechushav",
    "SemelMikzoank", "ShaotAvodaBederechKlalikaritNK", "ShaotAvodaLemaaseikaritNK",
    "SugChozemechushav", "SugMachalaPachotmechushav", "SugTeunaPachotmechushav",
    "MigzarTziburiAnafi", "TatTaasuka_Zman", "ChodeshKodem", "ChodeshKodemShaa",
    "MimaHaMigbala", "Mismachim", "Modaot", "OfenAcher", "Oved30", "PniyaLmaasik"
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
      -(RamatDat:BituachLeumi)
    )
  
  return(df)
}

