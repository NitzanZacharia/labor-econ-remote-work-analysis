# test-pretrend_wald_test.R
# Unit tests for run_pretrend_joint_test() (Phase 1c), against a small synthetic fixest model
# fit directly with i(ShnatSeker, ref=2019) + i(ShnatSeker, Mother, ref=2019) -- the exact
# specification run_diagnostics() uses -- rather than depending on run_diagnostics() itself or the
# project's fixture CSVs.

make_pretrend_model <- function() {
  set.seed(3)
  n <- 2000
  df <- data.frame(
    ShnatSeker = sample(c(2017, 2018, 2019, 2021, 2022, 2023), n, replace = TRUE),
    Mother     = sample(0:1, n, replace = TRUE),
    Employed   = sample(0:1, n, replace = TRUE),
    IDPUF      = sample(1:500, n, replace = TRUE)
  )
  fixest::feols(
    Employed ~ Mother + i(ShnatSeker, ref = 2019) + i(ShnatSeker, Mother, ref = 2019),
    data = df, cluster = ~IDPUF
  )
}

test_that("run_pretrend_joint_test returns a Wald test restricted to exactly the 2 pre-2020 terms", {
  m <- make_pretrend_model()
  w <- suppressMessages(run_pretrend_joint_test(m))

  expect_true(all(c("stat", "p", "df1", "df2", "vcov") %in% names(w)))
  expect_equal(w$df1, 2)  # exactly ShnatSeker::2017:Mother and ShnatSeker::2018:Mother
  expect_true(w$p >= 0 && w$p <= 1)
})

test_that("run_pretrend_joint_test's keep pattern does not pick up post-2020 Mother:year terms", {
  m <- make_pretrend_model()
  coefs <- names(coef(m))
  post_period_terms <- grep("ShnatSeker::(2021|2022|2023):Mother", coefs, value = TRUE)
  expect_true(length(post_period_terms) == 3)  # sanity: these terms do exist in the model

  w <- suppressMessages(run_pretrend_joint_test(m))
  expect_equal(w$df1, 2)  # confirms none of the 3 post-period terms leaked into the joint test
})

# ── Integration: couple this to the REAL run_diagnostics()-produced model ────────────────────
# The two tests above are valuable for their exact, hand-verifiable df/regex checks, but they run
# entirely against make_pretrend_model()'s own independently hand-built formula -- if
# Diagnostics.R's actual pretrend_model formula ever changes (different controls, a different ref
# year, an added Mother-interacted term), these tests would keep passing against their own frozen
# copy while run_pretrend_joint_test() could silently mis-specify the Wald restriction set in
# production. This test closes that gap by feeding the REAL run_diagnostics() output in.
#
# Deliberately NOT built from the shared fixtures_dir CSVs: those only cover survey years
# 2019/2021-2023 (no 2017/2018 at all -- confirmed empirically), so wald()'s pre-2020 regex
# matches zero terms against them and degenerates to a bare NA rather than a proper Wald object.
# This builds its own minimal temp-CSV fixture spanning 2017/2018/2019/2021, following the same
# self-contained-temp-fixture convention test-data_processing.R's "differs by Post period" test
# already uses for the same class of reason (the shared fixtures don't cover what's needed here).
test_that("run_pretrend_joint_test works against the real run_diagnostics()-produced model, not just a hand-built one", {
  range_boundary_cols <- c(
    "Yeladim0_1Prat", "Yeladim15_17Prat", "MisparHachlafa", "YachasKirvaNK",
    "MisparNefashotGilAvodaV2007", "MisparPrat", "ChipusAvodaSherutTaasuka",
    "ChipusAvodaOfenAcher", "EizeChozemechushav", "ChodeshKodemShaa",
    "MimaHaMigbala", "PniyaLmaasik", "RamatDat", "BituachLeumi"
  )
  # run_diagnostics()'s own NA-audit "peek" section select()s these raw columns unconditionally
  # (even though the peek itself filters to 0 rows here) -- they must exist or select() errors.
  diagnostics_peek_cols <- c(
    "Oved35Shaot", "MisraMelea", "SibaLeAvodaChelkit", "AvadShanaAchrona",
    "KamaChodashimAvadBashana", "SibaLoAvadHashana", "ShaotIkarit"
  )
  make_diag_row <- function(IDPUF, ShnatSeker, mother, employed, ctrl_alt) {
    row <- tibble::tibble(
      IDPUF = IDPUF, ShnatSeker = ShnatSeker, Min = 2, GilNK = if (ctrl_alt) 4 else 5,
      MisparYeladimAd17MB = if (mother) 1 else 0, GilYeledTzairMBNK = if (mother) 2 else 0,
      Muasak = if (employed) 1 else 2, AvodaMeHaBayit = NA,
      ShaotAvodaBederechKlalNK = 3, TeudaGvoha = if (ctrl_alt) 1 else 2,
      SemelEretzLeda = 10, DargatNayadut = 1, MishlachYad_ISCO_08_2 = "100", MachozYishuvAvoda = 1,
      Leom = 1, MatzavMishpachti = if (ctrl_alt) 1 else 2, Dat = if (ctrl_alt) 1 else 2,
      MachozMegurim = if (ctrl_alt) 1 else 2, MisparHorimYechidim = 0,
      AvadMeHaBayit = NA, KamaShaot = NA, ShaotAvodaLeMaase = 40, MishkalSofi = 1
    )
    for (col in range_boundary_cols) row[[col]] <- 0
    for (col in diagnostics_peek_cols) row[[col]] <- 0
    row
  }

  set.seed(1)
  idpuf <- 90001
  rows <- list()
  for (yr in c(2017, 2018, 2019, 2021)) {
    mother_pat <- rep(c(0, 1), length.out = 16)
    emp_pat    <- sample(c(0, 1), 16, replace = TRUE, prob = c(0.4, 0.6))
    for (i in 1:16) {
      rows[[length(rows) + 1]] <- make_diag_row(idpuf, yr, mother_pat[i], emp_pat[i], i %% 2 == 0)
      idpuf <- idpuf + 1
    }
  }
  synth <- dplyr::bind_rows(rows)

  tmp_dir <- tempfile("pretrend_fixture_")
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)
  readr::write_csv(synth, file.path(tmp_dir, "synth.csv"))

  cleaned <- load_and_clean_data(tmp_dir)
  with_null_device({
    out <- capture.output(diag_res <- run_diagnostics(cleaned))
  })

  w <- suppressMessages(run_pretrend_joint_test(diag_res$pretrend_model))

  expect_true(all(c("stat", "p", "df1", "df2", "vcov") %in% names(w)))
  expect_equal(w$df1, 2)
  expect_true(is.finite(w$stat))
  expect_true(w$p >= 0 && w$p <= 1)
})
