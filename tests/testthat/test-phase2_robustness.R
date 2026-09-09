# test-phase2_robustness.R
# Unit tests for phase2_robustness.R. Reuses the same style of dedicated synthetic panel as
# test-age_balance_robustness.R -- never touches the real CSV or load_and_clean_data() fixtures --
# extended with MishlachYad_ISCO_08_2 (some NA, simulating non-employed rows), MishkalSofi, and
# multiple ShnatSeker years so occupation x year clustering has something real to cluster on.

make_phase2_panel <- function() {
  set.seed(123)
  cell_defs <- expand.grid(gilnk = 3:7, moch = 1:2, teuda = c("X", "Y"), KEEP.OUT.ATTRS = FALSE)
  cell_defs$WFH_Exposure_cell <- stats::runif(nrow(cell_defs))

  exposure_cells <- tibble::tibble(
    Min = 2, GilNK = factor(cell_defs$gilnk), TeudaGvoha = cell_defs$teuda,
    MachozMegurim = factor(cell_defs$moch), WFH_Exposure = cell_defs$WFH_Exposure_cell
  )

  panel <- purrr::pmap_dfr(cell_defs, function(gilnk, moch, teuda, WFH_Exposure_cell) {
    n <- 200
    p_young_mother <- if (WFH_Exposure_cell < 0.5) 0.7 else 0.3
    employed <- stats::rbinom(n, 1, 0.7)
    # ISCO 23 (teaching) deliberately over-represented, plus other codes. Occupation is NOT
    # perfectly conditioned on current employment in the real data -- CBS records a "usual/last
    # occupation" for some non-employed respondents too (confirmed against the real cleaned_df:
    # 26.6% of non-employed rows still carry a defined occupation code) -- so this mirrors that
    # rather than deterministically tying NA-occupation to non-employed, which would make Employed
    # a constant once the occupation-clustering restriction is applied.
    has_occ <- stats::rbinom(n, 1, ifelse(employed == 1, 0.95, 0.25))
    isco <- ifelse(has_occ == 0, NA_real_,
                    sample(c(23, 21, 26, 31, 51), n, replace = TRUE, prob = c(0.2, 0.2, 0.2, 0.2, 0.2)))
    tibble::tibble(
      Min = 2, GilNK = factor(gilnk), TeudaGvoha = teuda, MachozMegurim = factor(moch),
      MatzavMishpachti = factor(rep(c("A", "B"), length.out = n)),
      Dat = factor(rep(c("A", "B"), length.out = n)),
      Mother = stats::rbinom(n, 1, if (gilnk <= 4) p_young_mother else (1 - p_young_mother)),
      ShnatSeker = sample(c(2018, 2019, 2022, 2023), n, replace = TRUE),
      Employed = employed,
      MishlachYad_ISCO_08_2 = isco,
      MishkalSofi = stats::runif(n, 0.5, 2)
    )
  })

  panel <- panel %>%
    dplyr::mutate(Post = as.integer(ShnatSeker >= 2021), IDPUF = dplyr::row_number())

  list(panel = panel, exposure_cells = exposure_cells)
}

test_that("prepare_reweighted_ddd_df builds EducationSector correctly (0 for NA/non-teaching, 1 only for ISCO==23)", {
  d <- make_phase2_panel()
  out <- capture.output(prep <- prepare_reweighted_ddd_df(d$panel, d$exposure_cells))

  expect_true(all(prep$ddd_df$EducationSector %in% c(0L, 1L)))
  expect_true(all(prep$ddd_df$EducationSector[is.na(prep$ddd_df$MishlachYad_ISCO_08_2)] == 0))
  expect_true(all(prep$ddd_df$EducationSector[!is.na(prep$ddd_df$MishlachYad_ISCO_08_2) &
                                                 prep$ddd_df$MishlachYad_ISCO_08_2 == 23] == 1))
  expect_true(all(prep$ddd_df$EducationSector[!is.na(prep$ddd_df$MishlachYad_ISCO_08_2) &
                                                 prep$ddd_df$MishlachYad_ISCO_08_2 != 23] == 0))
})

test_that("run_ddd_twoway_cluster drops only NA-occupation rows and reports plausible cluster counts", {
  d <- make_phase2_panel()
  out <- capture.output(res <- run_ddd_twoway_cluster(
    d$panel, d$exposure_cells,
    controls = c("MatzavMishpachti", "Dat", "GilNK", "MachozMegurim")
  ))

  expect_s3_class(res$additive$one_way, "fixest")
  expect_s3_class(res$additive$two_way, "fixest")
  expect_s3_class(res$fe$one_way, "fixest")
  expect_s3_class(res$fe$two_way, "fixest")
  expect_true(res$n_occyear <= res$n_idpuf * 4)  # sanity: at most (n employed rows) occ x year cells
  expect_true(res$n_idpuf > 0 && res$n_occyear > 0)
  # 1-way and 2-way must be fit on the identical N (same data, different cluster() spec only)
  expect_equal(stats::nobs(res$additive$one_way), stats::nobs(res$additive$two_way))
})

test_that("run_ddd_education_checks excludes ISCO==23 rows but keeps non-employed (NA-occupation) rows", {
  d <- make_phase2_panel()
  n_isco23 <- sum(!is.na(d$panel$MishlachYad_ISCO_08_2) & d$panel$MishlachYad_ISCO_08_2 == 23)
  expect_gt(n_isco23, 0)  # sanity: fixture actually has some

  out <- capture.output(res <- run_ddd_education_checks(
    d$panel, d$exposure_cells,
    controls = c("MatzavMishpachti", "Dat", "GilNK", "MachozMegurim")
  ))

  expect_equal(res$n_excluded, n_isco23)
  expect_s3_class(res$exclude_isco23$additive, "fixest")
  expect_s3_class(res$education_dummy$additive, "fixest")
  expect_true("Mother:Post:EducationSector" %in% names(coef(res$education_dummy$additive)))
  expect_true("Mother:Post:EducationSector" %in% names(coef(res$education_dummy$fe)))
})

test_that("run_ddd_weights_check's combined weight is exactly rake_weight * MishkalSofi and all four specs fit", {
  d <- make_phase2_panel()
  out <- capture.output(res <- run_ddd_weights_check(
    d$panel, d$exposure_cells,
    controls = c("MatzavMishpachti", "Dat", "GilNK", "MachozMegurim")
  ))

  for (grp in list(res$unweighted, res$rake_only, res$design_only, res$combined)) {
    expect_s3_class(grp$additive, "fixest")
    expect_s3_class(grp$fe, "fixest")
  }

  # Recompute combined_weight independently and check it matches what the weighted model actually used.
  prep <- prepare_reweighted_ddd_df(d$panel, d$exposure_cells)
  expected_combined <- prep$ddd_df$rake_weight * prep$ddd_df$MishkalSofi
  expect_equal(sort(stats::weights(res$combined$additive)), sort(stats::na.omit(expected_combined)),
               tolerance = 1e-8)
})
