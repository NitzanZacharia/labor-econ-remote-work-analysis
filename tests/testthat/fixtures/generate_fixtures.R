# generate_fixtures.R
# Generates the two synthetic fixture CSVs (sample_2019_Data.csv, sample_2021_Data.csv) used by
# the test suite. 100% synthetic, invented values — no real CBS microdata. Only the columns
# load_and_clean_data() actually references (by name, in filters/mutates/factor-conversion) or
# needs as boundary markers for its 7 positional range-drops are included; everything else in the
# real raw CSVs is irrelevant to what these tests check. Re-run this script (`Rscript
# tests/testthat/fixtures/generate_fixtures.R` from the repo root) to regenerate the CSVs if this
# spec ever changes — the row-by-row plan here is also mirrored (by IDPUF) in
# test-data_processing.R's expectations, so keep the two in sync if you edit this file.
library(tidyverse)

# ── Column order ─────────────────────────────────────────────────────────────
# Columns 1-19: everything load_and_clean_data() reads/uses by name.
# Columns 20-33: 7 adjacent boundary-column pairs, one pair per positional range-drop in
# data_processing.R (-(a:b)). Adjacent placement means each range drops exactly its 2 boundary
# columns and nothing else, so none of columns 1-19 can accidentally get caught in a range.
range_boundary_cols <- c(
  "Yeladim0_1Prat", "Yeladim15_17Prat",
  "MisparHachlafa", "YachasKirvaNK",
  "MisparNefashotGilAvodaV2007", "MisparPrat",
  "ChipusAvodaSherutTaasuka", "ChipusAvodaOfenAcher",
  "EizeChozemechushav", "ChodeshKodemShaa",
  "MimaHaMigbala", "PniyaLmaasik",
  "RamatDat", "BituachLeumi"
)

# Extra raw columns referenced only by Diagnostics.R's NA-audit peek (select() of specific raw
# fields for rows where Employed is NA) -- not used by load_and_clean_data() itself, but must
# exist for run_diagnostics() to run against these fixtures without a "column doesn't exist" error.
diagnostics_peek_cols <- c(
  "Oved35Shaot", "MisraMelea", "SibaLeAvodaChelkit", "AvadShanaAchrona",
  "KamaChodashimAvadBashana", "SibaLoAvadHashana", "ShaotIkarit", "AvadMeHaBayit", "KamaShaot"
)

make_row <- function(IDPUF, ShnatSeker, Min, GilNK, MisparYeladimAd17MB, GilYeledTzairMBNK,
                      Muasak, AvodaMeHaBayit, ShaotAvodaBederechKlalNK, TeudaGvoha,
                      SemelEretzLeda, DargatNayadut, MishlachYad_ISCO_08_2, MachozYishuvAvoda,
                      Leom, MatzavMishpachti, Dat, MachozMegurim, MisparHorimYechidim) {
  row <- tibble(
    IDPUF = IDPUF, ShnatSeker = ShnatSeker, Min = Min, GilNK = GilNK,
    MisparYeladimAd17MB = MisparYeladimAd17MB, GilYeledTzairMBNK = GilYeledTzairMBNK,
    Muasak = Muasak, AvodaMeHaBayit = AvodaMeHaBayit,
    ShaotAvodaBederechKlalNK = ShaotAvodaBederechKlalNK, TeudaGvoha = TeudaGvoha,
    SemelEretzLeda = SemelEretzLeda, DargatNayadut = DargatNayadut,
    MishlachYad_ISCO_08_2 = MishlachYad_ISCO_08_2, MachozYishuvAvoda = MachozYishuvAvoda,
    Leom = Leom, MatzavMishpachti = MatzavMishpachti, Dat = Dat, MachozMegurim = MachozMegurim,
    MisparHorimYechidim = MisparHorimYechidim
  )
  for (col in range_boundary_cols) row[[col]] <- 0
  for (col in diagnostics_peek_cols) row[[col]] <- 0
  row
}

# ── Fixture 1: 2019 (pre-COVID; Post==0). 16 valid rows covering every edge-case code for
# ShaotAvodaBederechKlalNK (0-12, 99), TeudaGvoha (0-9, 99), SemelEretzLeda (1-16),
# DargatNayadut (0-8), Muasak (1/2/NA), Leom (1/2/3) — plus 3 rows designed to be filtered out
# (Min!=2, GilNK out of 3:7 range).
fixture_2019 <- bind_rows(
  make_row(2019001, 2019, 2, 3, 0, 0, 1, NA, 0, 0, 10, 1, 100, 1, 1, 1, 1, 1, 0),
  make_row(2019002, 2019, 2, 4, 1, 1, 2, NA, 1, 1, 1, 2, 101, 2, 2, 2, 2, 2, 1),
  make_row(2019003, 2019, 2, 5, 0, 0, NA, NA, 2, 2, 2, 3, 102, 3, 3, 3, 3, 3, 0),
  make_row(2019004, 2019, 2, 6, 2, 2, 1, NA, 3, 3, 3, 4, 103, 4, 1, 4, 4, 4, 2),
  make_row(2019005, 2019, 2, 7, 0, 0, 1, NA, 4, 4, 4, 5, 104, 5, 1, 5, 5, 5, 0),
  make_row(2019006, 2019, 2, 3, 1, 1, 1, NA, 5, 5, 5, 6, 105, 6, 1, 1, 1, 6, 1),
  make_row(2019007, 2019, 2, 4, 0, 0, 1, NA, 6, 6, 6, 7, 106, 7, 1, 2, 2, 7, 0),
  make_row(2019008, 2019, 2, 5, 1, 3, 1, NA, 7, 7, 7, 8, 107, 1, 1, 3, 3, 1, 1),
  make_row(2019009, 2019, 2, 6, 0, 0, 1, NA, 8, 8, 8, 0, 108, 2, 1, 4, 4, 2, 0),
  make_row(2019010, 2019, 2, 7, 1, 4, 1, NA, 9, 9, 9, 1, 109, 3, 1, 5, 5, 3, 1),
  make_row(2019011, 2019, 2, 3, 0, 0, 1, NA, 10, 99, 11, 2, 110, 4, 1, 1, 1, 4, 0),
  make_row(2019012, 2019, 2, 4, 1, 5, 1, NA, 11, 0, 12, 3, 111, 5, 1, 2, 2, 5, 1),
  make_row(2019013, 2019, 2, 5, 0, 0, 1, NA, 12, 1, 13, 4, 112, 6, 1, 3, 3, 6, 0),
  make_row(2019014, 2019, 2, 6, 1, 1, 1, NA, 99, 2, 14, 5, 113, 7, 1, 4, 4, 7, 1),
  make_row(2019015, 2019, 2, 7, 0, 0, 1, NA, 0, 3, 15, 6, 114, 1, 1, 5, 5, 1, 0),
  make_row(2019016, 2019, 2, 3, 1, 2, 1, NA, 0, 4, 16, 7, 115, 2, 1, 1, 1, 2, 1),
  # filtered out: wrong sex
  make_row(2019017, 2019, 1, 4, 0, 0, 1, NA, 1, 1, 1, 1, 116, 3, 1, 1, 1, 1, 0),
  # filtered out: age group below range (GilNK==2)
  make_row(2019018, 2019, 2, 2, 0, 0, 1, NA, 1, 1, 1, 1, 117, 4, 1, 1, 1, 1, 0),
  # filtered out: age group above range (GilNK==8)
  make_row(2019019, 2019, 2, 8, 0, 0, 1, NA, 1, 1, 1, 1, 118, 5, 1, 1, 1, 1, 0),
  # Checkpoint 5 (Gender Placebo Test): Min==1 (men) rows. Invisible to every existing test that
  # calls load_and_clean_data(fixtures_dir) with the default sex_filter="women" (excluded by the
  # same Min filter that already excludes IDPUF 2019017 above) -- only surfaced when
  # sex_filter="men" is passed explicitly.
  make_row(2019101, 2019, 1, 4, 0, 0, 1, NA, 2, 2, 3, 2, 150, 1, 1, 1, 1, 1, 0),
  make_row(2019102, 2019, 1, 5, 1, 2, 1, NA, 6, 5, 10, 1, 151, 2, 1, 2, 2, 2, 1),
  make_row(2019103, 2019, 1, 6, 0, 0, 2, NA, 0, 3, 1, 0, 152, 3, 2, 1, 1, 3, 0),
  make_row(2019104, 2019, 1, 3, 2, 1, 1, NA, 7, 6, 2, 3, 153, 4, 1, 1, 2, 1, 2),
  make_row(2019105, 2019, 1, 7, 0, 0, 1, NA, 4, 4, 9, 4, 154, 5, 1, 2, 1, 2, 0),
  make_row(2019106, 2019, 1, 4, 1, 3, 1, NA, 8, 7, 11, 5, 155, 6, 1, 1, 1, 3, 1)
)

# ── Fixture 2: 2021-2023 (post-COVID; Post==1, WFH defined). 5 valid rows exercising WFH and
# Post/year filtering, plus 1 row with ShnatSeker==2020 that must be filtered out entirely.
fixture_2021 <- bind_rows(
  make_row(2021001, 2021, 2, 4, 1, 2, 1, 1, 6, 5, 10, 2, 200, 1, 1, 1, 1, 1, 0),
  make_row(2021002, 2021, 2, 5, 0, 0, 1, 0, 7, 6, 1, 1, 201, 2, 2, 2, 2, 2, 1),
  make_row(2021003, 2021, 2, 6, 2, 3, 2, 1, 0, 99, 16, 8, 202, 3, 1, 3, 3, 3, 2),
  make_row(2021004, 2022, 2, 7, 0, 0, NA, 0, 9, 3, 7, 5, 203, 4, 3, 4, 4, 4, 0),
  # filtered out: transitional year excluded
  make_row(2021005, 2020, 2, 3, 1, 1, 1, 1, 5, 2, 2, 3, 204, 1, 1, 1, 1, 1, 0),
  make_row(2021006, 2023, 2, 4, 3, 4, 1, 1, 10, 4, 9, 6, 205, 2, 5, 5, 5, 5, 1),
  # Checkpoint 5: more Min==1 (men) rows, post-period, same invisibility guarantee as above.
  make_row(2021101, 2021, 1, 5, 1, 2, 1, 1, 6, 5, 10, 2, 250, 2, 1, 2, 2, 2, 1),
  make_row(2021102, 2021, 1, 6, 0, 0, 1, 0, 7, 3, 1, 1, 251, 3, 2, 1, 1, 3, 0),
  make_row(2021103, 2022, 1, 4, 1, 4, 1, 1, 9, 6, 2, 3, 252, 4, 1, 1, 2, 1, 2),
  make_row(2021104, 2023, 1, 3, 0, 0, 2, 0, 0, 4, 9, 0, 253, 5, 1, 2, 1, 2, 0)
)

write_csv(fixture_2019, file.path("tests", "testthat", "fixtures", "sample_2019_Data.csv"))
write_csv(fixture_2021, file.path("tests", "testthat", "fixtures", "sample_2021_Data.csv"))

message("Wrote sample_2019_Data.csv (", nrow(fixture_2019), " rows) and sample_2021_Data.csv (",
        nrow(fixture_2021), " rows) to tests/testthat/fixtures/")
