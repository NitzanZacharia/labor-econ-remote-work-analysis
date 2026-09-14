# test-furlough_diagnostics.R
# Unit tests for check_furlough_incidence() (scripts/furlough_diagnostics.R). Small synthetic
# tibbles throughout -- this function only aggregates/reports on columns already produced by
# data_processing.R's Furloughed/Employed_strict derivation, so no real pipeline machinery is
# needed to exercise it.

test_that("part (a): furlough rate by year is computed correctly", {
  synth <- tibble::tibble(
    ShnatSeker = c(2019, 2019, 2019, 2021, 2021),
    Muasak     = c(1, 1, 2, 1, 1),
    Furloughed = c(0, 0, 0, 1, 0)
  )
  out <- capture.output(res <- check_furlough_incidence(synth))

  expect_equal(res$by_year$ShnatSeker, c(2019, 2021))
  expect_equal(res$by_year$n_employed, c(2, 2))       # Muasak==2 row excluded
  expect_equal(res$by_year$n_furloughed, c(0, 1))
  expect_equal(res$by_year$rate, c(0, 50))
})

test_that("part (b): degrades gracefully when AvadBeshavua is absent", {
  synth <- tibble::tibble(ShnatSeker = 2021, Muasak = 1, Furloughed = 0)
  expect_message(
    res <- check_furlough_incidence(synth),
    "AvadBeshavua"
  )
  expect_false(res$consistency$available)
})

test_that("part (b): warns when SibaNeedar is populated but AvadBeshavua != 4", {
  synth <- tibble::tibble(
    ShnatSeker  = rep(2021, 3),
    Muasak      = rep(1, 3),
    Furloughed  = c(1, 0, 0),
    SibaNeedar  = c(9, 5, NA),
    AvadBeshavua = c(4, 1, 1)   # row 2 is inconsistent: SibaNeedar populated but AvadBeshavua != 4
  )
  expect_warning(
    out <- capture.output(res <- check_furlough_incidence(synth)),
    "may not fully hold"
  )
  expect_equal(res$consistency$n, 2)          # 2 rows with SibaNeedar populated
  expect_equal(res$consistency$consistent, 1)  # row 1
  expect_equal(res$consistency$inconsistent, 1) # row 2
})

test_that("part (b): no warning when SibaNeedar population is fully consistent with AvadBeshavua==4", {
  synth <- tibble::tibble(
    ShnatSeker   = rep(2021, 2),
    Muasak       = rep(1, 2),
    Furloughed   = c(1, 0),
    SibaNeedar   = c(9, 5),
    AvadBeshavua = c(4, 4)
  )
  expect_no_warning(out <- capture.output(res <- check_furlough_incidence(synth)))
  expect_equal(res$consistency$inconsistent, 0)
})

test_that("part (c): degrades gracefully when df_with_quartile is NULL or lacks WFH_Exposure_Q", {
  synth <- tibble::tibble(ShnatSeker = 2021, Muasak = 1, Furloughed = 0)

  expect_message(res1 <- check_furlough_incidence(synth, df_with_quartile = NULL), "quartile")
  expect_null(res1$by_quartile)

  no_q <- tibble::tibble(ShnatSeker = 2021, Muasak = 1, Furloughed = 0, Post = 1, Mother = 0)
  expect_message(res2 <- check_furlough_incidence(synth, df_with_quartile = no_q), "WFH_Exposure_Q")
  expect_null(res2$by_quartile)
})

test_that("part (c): furlough rate by Post x Mother x WFH_Exposure quartile is computed correctly", {
  synth <- tibble::tibble(ShnatSeker = 2021, Muasak = 1, Furloughed = 0)  # unused by part (c)

  df_q <- tibble::tibble(
    Muasak          = c(1, 1, 1, 1, 1, 1),
    Furloughed      = c(1, 0, 0, 0, 0, 0),
    Post            = c(1, 1, 1, 1, 0, 0),
    Mother          = c(1, 1, 0, 0, 1, 0),
    WFH_Exposure_Q  = c(1, 1, 1, 4, 1, 1)
  )
  out <- capture.output(res <- check_furlough_incidence(synth, df_with_quartile = df_q))

  q1_mother_post1 <- res$by_quartile %>%
    dplyr::filter(Post == 1, Mother == 1, WFH_Exposure_Q == 1)
  expect_equal(q1_mother_post1$n_employed, 2)   # rows 1 (furloughed) and 2
  expect_equal(q1_mother_post1$n_furloughed, 1)
  expect_equal(q1_mother_post1$rate, 50)

  q1_nonmother_post1 <- res$by_quartile %>%
    dplyr::filter(Post == 1, Mother == 0, WFH_Exposure_Q == 1)
  expect_equal(q1_nonmother_post1$n_employed, 1)
  expect_equal(q1_nonmother_post1$rate, 0)
})

test_that("returns the documented structure", {
  synth <- tibble::tibble(ShnatSeker = 2021, Muasak = 1, Furloughed = 0)
  out <- capture.output(res <- check_furlough_incidence(synth))
  expect_setequal(names(res), c("by_year", "consistency", "by_quartile"))
})
