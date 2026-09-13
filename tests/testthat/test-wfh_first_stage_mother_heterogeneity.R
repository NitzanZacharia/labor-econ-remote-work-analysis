# test-wfh_first_stage_mother_heterogeneity.R
# Unit tests for check_wfh_first_stage_by_mother() (scripts/wfh_first_stage_mother_heterogeneity.R).
# Follows test-wfh_first_stage_check.R's make_first_stage_panel pattern (a pre-period slice run
# through the real build_exposure_cells() pipeline, joined back to a post-period panel by cell), but
# injects a WFH_Exposure -> WFH_RefWeek slope that differs by Mother, so the Mother:WFH_Exposure
# interaction can be checked against a known-true sign rather than just "runs without erroring."

make_first_stage_mother_panel <- function(slope = 2, mother_extra_slope = 3) {
  cells <- expand.grid(
    gilnk = 3:4, moch = 1:2, teuda = c("X", "Y"),
    KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE
  )

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

  make_block <- function(gilnk, moch, teuda) {
    tibble::tibble(
      Min = 2, GilNK = gilnk, TeudaGvoha = teuda, MachozMegurim = moch, ShnatSeker = 2022,
      MatzavMishpachti = factor(rep(c("A", "B"), length.out = 40)),
      Dat               = factor(rep(c("A", "B", "B", "A"), length.out = 40)),
      Mother = rep(c(0, 1), length.out = 40),
      Post = 1
    )
  }
  panel <- purrr::pmap_dfr(cells, function(gilnk, moch, teuda) make_block(gilnk, moch, teuda))

  panel %>%
    dplyr::left_join(exposure_cells, by = c("Min", "GilNK", "TeudaGvoha", "MachozMegurim")) %>%
    dplyr::mutate(
      slope_i     = slope + mother_extra_slope * Mother,
      p           = plogis(-1 + slope_i * WFH_Exposure),
      WFH_RefWeek = rbinom(dplyr::n(), 1, p),
      WFH_Share   = pmin(1, pmax(0, plogis(-1 + slope_i * WFH_Exposure) + rnorm(dplyr::n(), 0, 0.05)))
    )
}

test_that("check_wfh_first_stage_by_mother detects a known positive Mother:WFH_Exposure interaction (WFH_RefWeek)", {
  set.seed(101)
  panel  <- make_first_stage_mother_panel(slope = 1, mother_extra_slope = 4)
  result <- suppressWarnings(
    check_wfh_first_stage_by_mother(panel, controls = c("MatzavMishpachti", "Dat"))
  )

  expect_s3_class(result$refweek_reg, "fixest")
  refweek_coefs <- names(coef(result$refweek_reg))
  expect_true("WFH_Exposure:Mother" %in% refweek_coefs || "Mother:WFH_Exposure" %in% refweek_coefs)
  interaction_name <- intersect(c("WFH_Exposure:Mother", "Mother:WFH_Exposure"), refweek_coefs)
  expect_gt(unname(coef(result$refweek_reg)[interaction_name]), 0)
})

test_that("check_wfh_first_stage_by_mother also fits the continuous WFH_Share outcome", {
  set.seed(102)
  panel  <- make_first_stage_mother_panel(slope = 1, mother_extra_slope = 4)
  result <- suppressWarnings(
    check_wfh_first_stage_by_mother(panel, controls = c("MatzavMishpachti", "Dat"))
  )

  expect_s3_class(result$share_reg, "fixest")
  expect_true("WFH_Exposure" %in% names(coef(result$share_reg)))
})

test_that("check_wfh_first_stage_by_mother restricts estimation to Post == 1 rows", {
  set.seed(103)
  panel <- make_first_stage_mother_panel()
  panel_with_pre <- dplyr::bind_rows(
    panel,
    panel %>% dplyr::mutate(Post = 0, WFH_RefWeek = NA_real_, WFH_Share = NA_real_, ShnatSeker = 2018)
  )

  result <- suppressWarnings(
    check_wfh_first_stage_by_mother(panel_with_pre, controls = c("MatzavMishpachti", "Dat"))
  )

  expect_equal(nobs(result$refweek_reg), sum(panel_with_pre$Post == 1))
})

test_that("check_wfh_first_stage_by_mother returns a printable etable and the two underlying models", {
  set.seed(104)
  panel <- make_first_stage_mother_panel()
  out <- capture.output(res <- suppressWarnings(
    check_wfh_first_stage_by_mother(panel, controls = c("MatzavMishpachti", "Dat"))
  ))

  expect_type(res, "list")
  expect_setequal(names(res), c("refweek_reg", "share_reg", "table"))
  expect_s3_class(res$refweek_reg, "fixest")
  expect_s3_class(res$share_reg, "fixest")
})
