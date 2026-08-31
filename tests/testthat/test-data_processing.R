# test-data_processing.R
# Priority 1 (TESTING_BLUEPRINT.md §2): every recoding rule in load_and_clean_data(), plus the
# schema-presence test for the 7 positional column-drop ranges. This is the highest-value test
# file in the suite -- a silent error here corrupts every downstream number.

cleaned <- load_and_clean_data(fixtures_dir)

test_that("load_and_clean_data runs against fixtures and returns a non-empty data frame", {
  expect_s3_class(cleaned, "data.frame")
  expect_gt(nrow(cleaned), 0)
})

test_that("filter block: only Min==2, GilNK in 3:7, and the 6 valid survey years survive", {
  expect_true(all(cleaned$Min == 2))
  expect_true(all(as.integer(as.character(cleaned$GilNK)) %in% 3:7))
  expect_true(all(cleaned$ShnatSeker %in% c(2017, 2018, 2019, 2021, 2022, 2023)))
  # rows deliberately built to fail each filter condition must not survive
  expect_false(2019017 %in% cleaned$IDPUF)  # Min == 1
  expect_false(2019018 %in% cleaned$IDPUF)  # GilNK == 2
  expect_false(2019019 %in% cleaned$IDPUF)  # GilNK == 8
  expect_false(2021005 %in% cleaned$IDPUF)  # ShnatSeker == 2020
})

test_that("Employed: Muasak 1 -> 1; Muasak 2 -> 0; Muasak NA -> 0; never NA", {
  by_id <- function(id) cleaned$Employed[cleaned$IDPUF == id]
  expect_equal(by_id(2019001), 1L)  # Muasak == 1
  expect_equal(by_id(2019002), 0L)  # Muasak == 2
  expect_equal(by_id(2019003), 0L)  # Muasak == NA
  expect_equal(sum(is.na(cleaned$Employed)), 0)
})

test_that("WorkHoursCont: bins 0-10 map to their fixed range median", {
  hour_bin_median <- c(`0` = 0, `1` = 4, `2` = 11, `3` = 18, `4` = 25.5, `5` = 32,
                        `6` = 37, `7` = 42, `8` = 47, `9` = 54.5, `10` = 78.5)
  for (code in 0:10) {
    vals <- cleaned$WorkHoursCont[cleaned$ShaotAvodaBederechKlalNK == code &
                                     !is.na(cleaned$ShaotAvodaBederechKlalNK)]
    expect_gt(length(vals), 0)
    expect_true(all(vals == hour_bin_median[[as.character(code)]]))
  }
})

test_that("WorkHoursCont: code 99 -> NA", {
  vals <- cleaned$WorkHoursCont[cleaned$ShaotAvodaBederechKlalNK == 99]
  expect_gt(length(vals), 0)
  expect_true(all(is.na(vals)))
})

test_that("WorkHoursCont: codes 11/12 imputed as the median of the matching bin range", {
  hour_bin_median <- c(`0` = 0, `1` = 4, `2` = 11, `3` = 18, `4` = 25.5, `5` = 32,
                        `6` = 37, `7` = 42, `8` = 47, `9` = 54.5, `10` = 78.5)
  under35_codes <- cleaned$ShaotAvodaBederechKlalNK[cleaned$ShaotAvodaBederechKlalNK %in% 1:5]
  over35_codes  <- cleaned$ShaotAvodaBederechKlalNK[cleaned$ShaotAvodaBederechKlalNK %in% 6:10]
  expected_11 <- median(hour_bin_median[as.character(under35_codes)], na.rm = TRUE)
  expected_12 <- median(hour_bin_median[as.character(over35_codes)], na.rm = TRUE)

  actual_11 <- unique(cleaned$WorkHoursCont[cleaned$ShaotAvodaBederechKlalNK == 11])
  actual_12 <- unique(cleaned$WorkHoursCont[cleaned$ShaotAvodaBederechKlalNK == 12])
  expect_equal(actual_11, unname(expected_11))
  expect_equal(actual_12, unname(expected_12))
})

test_that("TeudaGvoha: 11 raw codes collapse into the 6 documented groups, 99 -> NA", {
  expected <- c(
    `2019001` = "Below High School",      # raw 0
    `2019002` = "Below High School",      # raw 1
    `2019003` = "High School (no matriculation)",  # raw 2
    `2019004` = "Matriculation (Bagrut)", # raw 3
    `2019005` = "Post-secondary, non-academic",    # raw 4
    `2019006` = "Academic Degree (BA/MA/PhD)",     # raw 5
    `2019007` = "Academic Degree (BA/MA/PhD)",     # raw 6
    `2019008` = "Academic Degree (BA/MA/PhD)",     # raw 7
    `2019009` = "Other/No Certificate",   # raw 8
    `2019010` = "Other/No Certificate"    # raw 9
  )
  for (id in names(expected)) {
    got <- as.character(cleaned$TeudaGvoha[cleaned$IDPUF == as.numeric(id)])
    expect_equal(got, unname(expected[id]), info = id)
  }
  # raw 99 -> NA
  expect_true(is.na(cleaned$TeudaGvoha[cleaned$IDPUF == 2019011]))
})

test_that("BirthContinent: 16 raw SemelEretzLeda codes map to the 6 documented continents, 16 -> NA", {
  expected <- c(
    `2019001` = "Israel",         # raw 10
    `2019002` = "Asia",           # raw 1
    `2019003` = "Africa",         # raw 2
    `2019004` = "Europe",         # raw 3
    `2019005` = "Europe",         # raw 4
    `2019006` = "Europe",         # raw 5
    `2019007` = "Asia",           # raw 6
    `2019008` = "Other",          # raw 7
    `2019009` = "Africa",         # raw 8
    `2019010` = "North America",  # raw 9
    `2019011` = "Asia",           # raw 11
    `2019012` = "Africa",         # raw 12
    `2019013` = "Europe",         # raw 13
    `2019014` = "Asia",           # raw 14
    `2019015` = "Africa"          # raw 15
  )
  for (id in names(expected)) {
    got <- as.character(cleaned$BirthContinent[cleaned$IDPUF == as.numeric(id)])
    expect_equal(got, unname(expected[id]), info = id)
  }
  # raw 16 -> NA
  expect_true(is.na(cleaned$BirthContinent[cleaned$IDPUF == 2019016]))
})

test_that("WorksOutsideLocality: DargatNayadut 1->0, 2-7->1, 0/8->NA", {
  expected <- c(
    `2019001` = 0L,  # raw 1
    `2019002` = 1L,  # raw 2
    `2019003` = 1L,  # raw 3
    `2019004` = 1L,  # raw 4
    `2019005` = 1L,  # raw 5
    `2019006` = 1L,  # raw 6
    `2019007` = 1L,  # raw 7
    `2019010` = 0L   # raw 1 (second occurrence)
  )
  for (id in names(expected)) {
    got <- cleaned$WorksOutsideLocality[cleaned$IDPUF == as.numeric(id)]
    expect_equal(got, unname(expected[id]), info = id)
  }
  # raw 8 and raw 0 -> NA
  expect_true(is.na(cleaned$WorksOutsideLocality[cleaned$IDPUF == 2019008]))  # raw 8
  expect_true(is.na(cleaned$WorksOutsideLocality[cleaned$IDPUF == 2019009]))  # raw 0
})

test_that("WFH: defined only for ShnatSeker >= 2021, NA pre-2021", {
  expect_true(all(is.na(cleaned$WFH[cleaned$ShnatSeker < 2021])))
  expect_equal(cleaned$WFH[cleaned$IDPUF == 2021001], 1)  # AvodaMeHaBayit == 1
  expect_equal(cleaned$WFH[cleaned$IDPUF == 2021002], 0)  # AvodaMeHaBayit == 0
})

test_that("Mother: derived from MisparYeladimAd17MB > 0", {
  expect_equal(cleaned$Mother[cleaned$IDPUF == 2019001], 0L)  # MisparYeladimAd17MB == 0
  expect_equal(cleaned$Mother[cleaned$IDPUF == 2019002], 1L)  # MisparYeladimAd17MB == 1
})

test_that("categorical controls are converted to factor, not left numeric", {
  for (col in c("MatzavMishpachti", "Dat", "GilNK", "MachozMegurim", "MisparHorimYechidim")) {
    expect_s3_class(cleaned[[col]], "factor")
  }
})

test_that("schema-presence: previously-dropped columns now survive; range-dropped columns are absent", {
  expect_true("DargatNayadut" %in% names(cleaned))
  expect_true("MachozYishuvAvoda" %in% names(cleaned))
  expect_true("Leom" %in% names(cleaned))
  expect_true("SemelEretzLeda" %in% names(cleaned))

  dropped_sample <- c("RamatDat", "BituachLeumi", "Yeladim0_1Prat", "Yeladim15_17Prat",
                       "MisparHachlafa", "YachasKirvaNK", "MisparNefashotGilAvodaV2007",
                       "MisparPrat", "ChipusAvodaSherutTaasuka", "ChipusAvodaOfenAcher",
                       "EizeChozemechushav", "ChodeshKodemShaa", "MimaHaMigbala", "PniyaLmaasik")
  for (col in dropped_sample) {
    expect_false(col %in% names(cleaned), info = col)
  }
})
