# test-wfh_first_stage_check.R
# Unit tests for check_wfh_first_stage_relevance() (scripts/wfh_first_stage_check.R). Builds a
# self-contained synthetic panel (following test-primary_ddd_mechanics.R's make_ddd_panel pattern:
# a pre-period 2017-2019 slice run through the real build_exposure_cells() pipeline, then a
# post-period panel joined back to it by cell) with a WFH_RefWeek outcome constructed to have a
# known relationship to WFH_Exposure, so the level and dynamic specs can be checked against a
# known-true sign/structure rather than just "runs without erroring."

make_first_stage_panel <- function(slope = 4, year_effect = 0) {
  cells <- expand.grid(
    gilnk = 3:4, moch = 1:2, teuda = c("X", "Y"),
    KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE
  )

  # Pre-period (2017-2019, Muasak == 1) rows -- one distinct occupation per demographic cell, so
  # build_exposure_cells() gives each cell a different WFH_Exposure once joined to a crosswalk with
  # varying tele_ext, exactly as main.R's assembly does.
  pre <- purrr::pmap_dfr(cells, function(gilnk, moch, teuda) {
    tibble::tibble(
      ShnatSeker = 2018, Muasak = 1, Min = 2,
      GilNK = gilnk, TeudaGvoha = teuda, MachozMegurim = moch,
      MishlachYad_ISCO_08_2 = 300 + gilnk * 10 + moch * 3 + match(teuda, c("X", "Y")),
      MishkalSofi = 1
    )
  })
  dn <- pre %>%
    dplyr::distinct(MishlachYad_ISCO_08_2) %>%
    dplyr::mutate(tele_ext = seq(0.1, 0.9, length.out = dplyr::n())) %>%
    dplyr::rename(ISCO2 = MishlachYad_ISCO_08_2)

  exposure_cells <- build_exposure_cells(pre, dn)

  # Post-period panel (2021-2023, WFH_RefWeek observed), 20 rows per cell-year.
  make_block <- function(gilnk, moch, teuda, year) {
    tibble::tibble(
      Min = 2, GilNK = gilnk, TeudaGvoha = teuda, MachozMegurim = moch, ShnatSeker = year,
      MatzavMishpachti = factor(rep(c("A", "B"), length.out = 20)),
      Dat               = factor(rep(c("A", "B", "B", "A"), length.out = 20)),
      Post = 1
    )
  }
  grid <- tidyr::expand_grid(cells, year = 2021:2023)
  panel <- purrr::pmap_dfr(
    grid, function(gilnk, moch, teuda, year) make_block(gilnk, moch, teuda, year)
  )

  panel %>%
    dplyr::left_join(exposure_cells, by = c("Min", "GilNK", "TeudaGvoha", "MachozMegurim")) %>%
    dplyr::mutate(
      year_idx    = ShnatSeker - 2021,
      p           = plogis(-1 + slope * WFH_Exposure + year_idx * year_effect * WFH_Exposure),
      WFH_RefWeek = rbinom(dplyr::n(), 1, p)
    )
}

test_that("check_wfh_first_stage_relevance detects a known positive WFH_Exposure -> WFH_RefWeek relationship", {
  set.seed(123)
  panel  <- make_first_stage_panel(slope = 4, year_effect = 0)
  result <- suppressWarnings(
    check_wfh_first_stage_relevance(panel, controls = c("MatzavMishpachti", "Dat"))
  )

  expect_s3_class(result$level_reg, "fixest")
  expect_true("WFH_Exposure" %in% names(coef(result$level_reg)))
  expect_gt(unname(coef(result$level_reg)["WFH_Exposure"]), 0)
})

test_that("check_wfh_first_stage_relevance's dynamic spec identifies a strengthening exposure gradient over years", {
  set.seed(456)
  panel  <- make_first_stage_panel(slope = 1, year_effect = 5)
  result <- suppressWarnings(
    check_wfh_first_stage_relevance(panel, controls = c("MatzavMishpachti", "Dat"))
  )

  expect_s3_class(result$dynamic_reg, "fixest")
  dynamic_coefs <- names(coef(result$dynamic_reg))
  interaction_terms <- setdiff(grep("WFH_Exposure", dynamic_coefs, value = TRUE), "WFH_Exposure")
  expect_true(length(interaction_terms) > 0)
  # 2022/2023 slopes should exceed the 2021 (reference) slope given year_effect > 0.
  expect_true(all(unname(coef(result$dynamic_reg)[interaction_terms]) > 0))
})

test_that("check_wfh_first_stage_relevance restricts estimation to Post == 1 rows", {
  set.seed(789)
  panel <- make_first_stage_panel()
  panel_with_pre <- dplyr::bind_rows(
    panel,
    panel %>% dplyr::mutate(Post = 0, WFH_RefWeek = NA_real_, ShnatSeker = 2018)
  )

  result <- suppressWarnings(
    check_wfh_first_stage_relevance(panel_with_pre, controls = c("MatzavMishpachti", "Dat"))
  )

  expect_equal(nobs(result$level_reg), sum(panel_with_pre$Post == 1))
})

test_that("check_wfh_first_stage_relevance returns a printable etable and the two underlying models", {
  set.seed(321)
  panel  <- make_first_stage_panel()
  result <- suppressWarnings(
    capture.output(res <- check_wfh_first_stage_relevance(panel, controls = c("MatzavMishpachti", "Dat")))
  )

  expect_type(res, "list")
  expect_setequal(names(res), c("level_reg", "dynamic_reg", "table"))
  expect_s3_class(res$level_reg, "fixest")
  expect_s3_class(res$dynamic_reg, "fixest")
})
