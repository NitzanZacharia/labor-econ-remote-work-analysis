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

test_that("WorkHoursCont: bins 0-10 map to their fixed range median, among employed rows", {
  # Employed == 1 restriction matches WorkHoursCont's own gating (see the dedicated gating test
  # below): a non-employed row with a populated ShaotAvodaBederechKlalNK code is correctly NA now,
  # not the bin median, so it must be excluded here rather than making this loop's `all(vals == ...)`
  # spuriously fail. 2019020/2019021 are dedicated employed exemplars for codes 1/2 specifically
  # because the only other fixture rows with those codes (2019002, 2019003) are non-employed.
  hour_bin_median <- c(`0` = 0, `1` = 4, `2` = 11, `3` = 18, `4` = 25.5, `5` = 32,
                        `6` = 37, `7` = 42, `8` = 47, `9` = 54.5, `10` = 78.5)
  for (code in 0:10) {
    vals <- cleaned$WorkHoursCont[cleaned$ShaotAvodaBederechKlalNK == code &
                                     !is.na(cleaned$ShaotAvodaBederechKlalNK) &
                                     cleaned$Employed == 1]
    expect_gt(length(vals), 0)
    expect_true(all(vals == hour_bin_median[[as.character(code)]]))
  }
})

test_that("WorkHoursCont: code 99 -> NA", {
  vals <- cleaned$WorkHoursCont[cleaned$ShaotAvodaBederechKlalNK == 99]
  expect_gt(length(vals), 0)
  expect_true(all(is.na(vals)))
})

test_that("WorkHoursCont: NA for non-employed rows regardless of their raw hours code", {
  # 2019002 (Muasak==2, code 1), 2019003 (Muasak==NA, code 2), 2021003 (Muasak==2, code 0),
  # 2021004 (Muasak==NA, code 9) all have a populated ShaotAvodaBederechKlalNK but are not
  # employed -- previously this mapped straight to a literal number (e.g. bin 0 -> 0.0),
  # indistinguishable from an employed person reporting that hours bin.
  non_employed_with_code <- c(2019002, 2019003, 2021003, 2021004)
  by_id <- function(id) cleaned$WorkHoursCont[cleaned$IDPUF == id]
  for (id in non_employed_with_code) {
    expect_equal(cleaned$Employed[cleaned$IDPUF == id], 0L)
    expect_true(is.na(by_id(id)), info = paste("IDPUF", id))
  }
})

test_that("WorkHoursCont: codes 11/12 are imputed from the matching bin range's median WITHIN the same Post period as the row being imputed", {
  hour_bin_median <- c(`0` = 0, `1` = 4, `2` = 11, `3` = 18, `4` = 25.5, `5` = 32,
                        `6` = 37, `7` = 42, `8` = 47, `9` = 54.5, `10` = 78.5)

  # The code-11 row (2019012) and code-12 row (2019013) in these fixtures are both Post==0
  # (2019), so their imputation must be computed from Post==0's OWN codes 1-5 / 6-10 -- not
  # pooled across the whole (both-period) sample. These fixtures' Post==1 women rows happen to
  # include ShaotAvodaBederechKlalNK == 6 and 7 (2021001/2021002); a pooled (pre-fix)
  # implementation would fold those into the code-12 median (giving 42), but the period-restricted
  # implementation must not -- expected_12 here (47) is deliberately different from that pooled
  # value, so a regression back to pooled imputation would be caught.
  # Employed == 1 restriction mirrors the donor-pool gate in data_processing.R -- without it,
  # 2019002/2019003 (non-employed, codes 1/2) would double-count against 2019020/2019021 (the
  # employed exemplars added for the WorkHoursCont-gating fix) and this test's own expectation
  # would silently diverge from what the real, gated computation produces.
  post0 <- cleaned[cleaned$Post == 0 & cleaned$Employed == 1, ]
  under35_codes <- post0$ShaotAvodaBederechKlalNK[post0$ShaotAvodaBederechKlalNK %in% 1:5]
  over35_codes  <- post0$ShaotAvodaBederechKlalNK[post0$ShaotAvodaBederechKlalNK %in% 6:10]
  expected_11 <- median(hour_bin_median[as.character(under35_codes)], na.rm = TRUE)
  expected_12 <- median(hour_bin_median[as.character(over35_codes)], na.rm = TRUE)

  actual_11 <- unique(cleaned$WorkHoursCont[cleaned$ShaotAvodaBederechKlalNK == 11])
  actual_12 <- unique(cleaned$WorkHoursCont[cleaned$ShaotAvodaBederechKlalNK == 12])
  expect_equal(actual_11, unname(expected_11))
  expect_equal(actual_12, unname(expected_12))
  expect_equal(unname(expected_12), 47)  # sanity anchor: the (would-be-pooled) alternative is 42
})

test_that("WorkHoursCont's code-11 imputation differs by Post period when the surrounding regular-hours codes differ", {
  # load_and_clean_data() reads from a folder of CSVs, so this builds a small, self-contained
  # temporary fixture (not the shared sample_2019_Data.csv/sample_2021_Data.csv) with two Post
  # periods whose codes 1-5 rows are deliberately different, so the code-11 imputed value must
  # differ by period if (and only if) the imputation is genuinely period-restricted.
  range_boundary_cols <- c(
    "Yeladim0_1Prat", "Yeladim15_17Prat", "MisparHachlafa", "YachasKirvaNK",
    "MisparNefashotGilAvodaV2007", "MisparPrat", "ChipusAvodaSherutTaasuka",
    "ChipusAvodaOfenAcher", "RamatDat", "BituachLeumi"
  )
  make_period_row <- function(IDPUF, ShnatSeker, ShaotAvodaBederechKlalNK) {
    row <- tibble::tibble(
      IDPUF = IDPUF, ShnatSeker = ShnatSeker, Min = 2, GilNK = 4,
      MisparYeladimAd17MB = 0, Muasak = 1, AvodaMeHaBayit = NA,
      ShaotAvodaBederechKlalNK = ShaotAvodaBederechKlalNK, TeudaGvoha = 1,
      SemelEretzLeda = 10, DargatNayadut = 1, MishlachYad_ISCO_08_2 = "100",
      Leom = 1, MatzavMishpachti = 1, Dat = 1, MachozMegurim = 1, MisparHorimYechidim = 0,
      AvadMeHaBayit = NA, KamaShaot = NA, ShaotAvodaLeMaase = NA
    )
    for (col in range_boundary_cols) row[[col]] <- 0
    row
  }

  tmp_dir <- tempfile("workhours_period_fixture_")
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)

  # Pre (2019, Post==0): codes 1 (-> 4) and 2 (-> 11); median = 7.5.
  # Post (2022, Post==1): codes 4 (-> 25.5) and 5 (-> 32); median = 28.75.
  synth <- dplyr::bind_rows(
    make_period_row(80001, 2019, 1),
    make_period_row(80002, 2019, 2),
    make_period_row(80003, 2019, 11),   # to be imputed from the 2019 (Post==0) pool -> 7.5
    make_period_row(80004, 2022, 4),
    make_period_row(80005, 2022, 5),
    make_period_row(80006, 2022, 11)    # to be imputed from the 2022 (Post==1) pool -> 28.75
  )
  readr::write_csv(synth, file.path(tmp_dir, "period_fixture.csv"))

  cleaned_period <- load_and_clean_data(tmp_dir)

  expect_equal(cleaned_period$WorkHoursCont[cleaned_period$IDPUF == 80003], 7.5)
  expect_equal(cleaned_period$WorkHoursCont[cleaned_period$IDPUF == 80006], 28.75)
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

# ── WFH block ───────────────────────────────────────────────────────────────
# CBS codes both yes/no items 1 = yes, 2 = no, 9 = unknown, blank = not asked. The fixtures now
# use those real codes (they previously used an impossible 1/0/NA), which is what lets the code-9
# case below actually be tested.
by_id <- function(col, id) cleaned[[col]][cleaned$IDPUF == id]

test_that("WFH: defined only for ShnatSeker >= 2021, NA pre-2021", {
  # pre-2021 rows carry a real ShaotAvodaLeMaase but an empty WFH module, so the year guard --
  # not merely missing inputs -- is what has to produce the NA
  expect_true(all(is.na(cleaned$WFH[cleaned$ShnatSeker < 2021])))
  expect_true(all(is.na(cleaned$WFH_RefWeek[cleaned$ShnatSeker < 2021])))
  expect_true(all(is.na(cleaned$WFH_Share[cleaned$ShnatSeker < 2021])))
})

test_that("WFH: code 1 -> 1, code 2 -> 0, code 9 ('unknown') -> NA, not asked -> NA", {
  expect_equal(by_id("WFH", 2021001), 1)   # AvodaMeHaBayit == 1
  expect_equal(by_id("WFH", 2021002), 0)   # AvodaMeHaBayit == 2
  expect_true(is.na(by_id("WFH", 2021003)))  # AvodaMeHaBayit == 9 -- must NOT become 0
  expect_true(is.na(by_id("WFH", 2021004)))  # AvodaMeHaBayit blank
})

test_that("WFH_RefWeek is independent of WFH: 'usually no' but worked from home all week", {
  # 6,182 real 2021 rows answer 2 to the usual item and 1 to the reference-week item
  expect_equal(by_id("WFH", 2021006), 0)
  expect_equal(by_id("WFH_RefWeek", 2021006), 1)
  expect_equal(by_id("WFH_RefWeek", 2021002), 0)
  expect_true(is.na(by_id("WFH_RefWeek", 2021003)))  # code 9
})

test_that("WFH_Hours / WFH_Share / WFH_Arrangement follow from the hours items", {
  # 20 of 40 hours from home
  expect_equal(by_id("WFH_Hours", 2021001), 20)
  expect_equal(by_id("WFH_Share", 2021001), 0.5)
  expect_equal(as.character(by_id("WFH_Arrangement", 2021001)), "Hybrid")

  # did not work from home -> zero hours, zero share, on-site (not NA)
  expect_equal(by_id("WFH_Hours", 2021002), 0)
  expect_equal(by_id("WFH_Share", 2021002), 0)
  expect_equal(as.character(by_id("WFH_Arrangement", 2021002)), "On-site")

  # 40 of 40 hours from home
  expect_equal(by_id("WFH_Share", 2021006), 1)
  expect_equal(as.character(by_id("WFH_Arrangement", 2021006)), "Fully remote")

  expect_true(is.na(by_id("WFH_Share", 2021003)))
  expect_true(is.na(by_id("WFH_Arrangement", 2021003)))
})

test_that("WFH_Share never exceeds 1 and is 0 or NA whenever WFH_RefWeek is not 1", {
  expect_true(all(cleaned$WFH_Share <= 1, na.rm = TRUE))
  expect_true(all(cleaned$WFH_Share[!is.na(cleaned$WFH_RefWeek) & cleaned$WFH_RefWeek == 0] == 0))
  expect_true(all(is.na(cleaned$WFH_Share[is.na(cleaned$WFH_RefWeek)])))
})

test_that("hour codes in the 90s are treated as codes, not as hour counts", {
  # KamaShaot == 97 paired with ShaotAvodaLeMaase == 97 is CBS's "irregular/unknown" code (every
  # one of the 73 such 2021 rows is paired this way), so hours/share must be NA even though the
  # yes/no items are answered. Only present on a men row, hence the second load.
  cleaned_men <- load_and_clean_data(fixtures_dir, sex_filter = "men")
  expect_equal(cleaned_men$WFH[cleaned_men$IDPUF == 2021101], 1)
  expect_equal(cleaned_men$WFH_RefWeek[cleaned_men$IDPUF == 2021101], 1)
  expect_true(is.na(cleaned_men$WFH_Hours[cleaned_men$IDPUF == 2021101]))
  expect_true(is.na(cleaned_men$WFH_Share[cleaned_men$IDPUF == 2021101]))
  expect_true(is.na(cleaned_men$WFH_Arrangement[cleaned_men$IDPUF == 2021101]))

  # employed but absent in the reference week -> usual item answered, ref-week item NA
  expect_equal(cleaned_men$WFH[cleaned_men$IDPUF == 2021103], 1)
  expect_true(is.na(cleaned_men$WFH_RefWeek[cleaned_men$IDPUF == 2021103]))
})

test_that("ISCO: disclosure-masked codes are flagged, and the 1-digit group is recovered", {
  # unmasked "200" -> numeric 200, ISCO1 == 2
  expect_equal(by_id("MishlachYad_ISCO_08_2", 2021001), 200)
  expect_false(by_id("ISCO_masked", 2021001))
  expect_equal(by_id("ISCO1", 2021001), 2)

  # fully masked "XX" -> no numeric code, no 1-digit fallback, but flagged
  expect_true(is.na(by_id("MishlachYad_ISCO_08_2", 2021003)))
  expect_true(by_id("ISCO_masked", 2021003))
  expect_true(is.na(by_id("ISCO1", 2021003)))

  # partially masked "7X" -> no 2-digit code, but the major group survives
  expect_true(is.na(by_id("MishlachYad_ISCO_08_2", 2021006)))
  expect_true(by_id("ISCO_masked", 2021006))
  expect_equal(by_id("ISCO1", 2021006), 7)

  # the flag is never NA, and is TRUE for exactly the rows carrying a masked code
  expect_false(any(is.na(cleaned$ISCO_masked)))
  expect_setequal(cleaned$IDPUF[cleaned$ISCO_masked], c(2019016, 2021003, 2021006))
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
