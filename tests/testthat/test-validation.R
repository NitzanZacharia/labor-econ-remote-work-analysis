# test-validation.R
# Checkpoint 1 (docs/ROADMAP.md): unit tests for validate_cleaned_df() against small synthetic
# tibbles, covering every hard-fail and soft-fail check from docs/LLD.md's "Validation &
# Thresholds" section in both its passing and triggering form.

make_valid_df <- function(n = 20) {
  tibble::tibble(
    Min                  = rep(2, n),
    GilNK                = factor(rep(3:7, length.out = n)),
    ShnatSeker           = rep(c(2017, 2018, 2019, 2021, 2022, 2023), length.out = n),
    Employed             = rep(c(0L, 1L), length.out = n),
    Mother               = rep(c(0L, 1L), length.out = n),
    Post                 = rep(c(0L, 1L), length.out = n),
    MatzavMishpachti     = factor(rep(1:2, length.out = n)),
    Dat                  = factor(rep(1:2, length.out = n)),
    MachozMegurim        = factor(rep(1:2, length.out = n)),
    TeudaGvoha           = factor(rep(1:2, length.out = n)),
    WorksOutsideLocality = rep(c(0L, 1L), length.out = n),
    WFH                  = rep(c(0, 1), length.out = n),
    WorkHoursCont        = rep(c(10, 20), length.out = n),
    BirthContinent       = factor(rep(c("Israel", "Asia"), length.out = n))
  )
}

# ── Hard-fail checks ─────────────────────────────────────────────────────────

test_that("validate_cleaned_df passes silently on a well-formed data frame", {
  expect_silent(validate_cleaned_df(make_valid_df()))
})

test_that("validate_cleaned_df with no sex_filter argument still defaults to women (Min==2)", {
  df <- make_valid_df()
  df$Min[1] <- 1
  expect_error(validate_cleaned_df(df), "Min")
})

test_that("validate_cleaned_df(sex_filter = 'men') passes on Min==1 data and rejects Min==2 data", {
  df_men <- make_valid_df()
  df_men$Min <- rep(1, nrow(df_men))
  expect_silent(validate_cleaned_df(df_men, sex_filter = "men"))
  expect_error(validate_cleaned_df(make_valid_df(), sex_filter = "men"), "Min")
})

test_that("validate_cleaned_df stops when Min != 2 is present", {
  df <- make_valid_df()
  df$Min[1] <- 1
  expect_error(validate_cleaned_df(df), "Min")
})

test_that("validate_cleaned_df stops when GilNK is outside 3:7", {
  df <- make_valid_df()
  df$GilNK <- factor(c("8", as.character(df$GilNK)[-1]), levels = c("3", "4", "5", "6", "7", "8"))
  expect_error(validate_cleaned_df(df), "GilNK")
})

test_that("validate_cleaned_df stops when ShnatSeker includes the excluded year 2020", {
  df <- make_valid_df()
  df$ShnatSeker[1] <- 2020
  expect_error(validate_cleaned_df(df), "ShnatSeker")
})

test_that("validate_cleaned_df stops when Employed has an NA", {
  df <- make_valid_df()
  df$Employed[1] <- NA_integer_
  expect_error(validate_cleaned_df(df), "Employed")
})

test_that("validate_cleaned_df stops when Mother has an NA", {
  df <- make_valid_df()
  df$Mother[1] <- NA_integer_
  expect_error(validate_cleaned_df(df), "Mother")
})

test_that("validate_cleaned_df stops when Post has an NA", {
  df <- make_valid_df()
  df$Post[1] <- NA_integer_
  expect_error(validate_cleaned_df(df), "Post")
})

test_that("validate_cleaned_df stops on a zero-row data frame", {
  df <- make_valid_df()[0, ]
  expect_error(validate_cleaned_df(df), "zero rows")
})

# ── Soft-fail checks ─────────────────────────────────────────────────────────

test_that("validate_cleaned_df warns when a regression control's NA rate exceeds 5%", {
  df <- make_valid_df(n = 40)
  df$TeudaGvoha[1:3] <- NA  # 3/40 = 7.5% > 5%
  expect_warning(validate_cleaned_df(df), "TeudaGvoha")
})

test_that("validate_cleaned_df does not warn when a regression control's NA rate is below 5%", {
  df <- make_valid_df(n = 40)
  df$TeudaGvoha[1] <- NA  # 1/40 = 2.5% < 5%
  expect_no_warning(validate_cleaned_df(df))
})

test_that("validate_cleaned_df warns when WorksOutsideLocality's NA rate exceeds ~20%", {
  df <- make_valid_df(n = 20)
  df$WorksOutsideLocality[1:5] <- NA  # 5/20 = 25% > 20%
  expect_warning(validate_cleaned_df(df), "WorksOutsideLocality")
})

test_that("validate_cleaned_df does not warn on WorksOutsideLocality at a real-data-typical ~17% NA", {
  df <- make_valid_df(n = 100)
  df$WorksOutsideLocality[1:17] <- NA
  expect_no_warning(validate_cleaned_df(df))
})

test_that("validate_cleaned_df warns when a comparative-stats-only variable's NA rate exceeds 70%", {
  df <- make_valid_df(n = 20)
  df$WFH[1:15] <- NA  # 15/20 = 75% > 70%
  expect_warning(validate_cleaned_df(df), "WFH")
})

test_that("validate_cleaned_df does not warn on WFH at a real-data-typical ~64% NA", {
  df <- make_valid_df(n = 100)
  df$WFH[1:64] <- NA
  expect_no_warning(validate_cleaned_df(df))
})
