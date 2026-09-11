# test-primary_ddd_mechanics.R
# Correctness/bounds companion to test-pipeline_smoke.R's existing smoke test of main.R's section
# 8a (the primary DDD: cell-based WFH_Exposure, two feols specs). That test only asserts
# expect_s3_class(..., "fixest") -- it never checks that the mechanism the decision memo argues
# for (docs/decisions/calibrated-exposure-and-cell-ddd.md) actually holds: that Spec 2's fully
# interacted cell FE absorbs WFH_Exposure's bare main effect as collinear, leaving identification
# to come from within-cell Mother/Post variation. This file builds a dedicated synthetic panel
# (following test-gender_placebo.R's run_gender_ddd_placebo pattern -- the fixtures are sized for
# schema tests, not for a saturated triple-interaction to be identified) with the exposure
# regressor built through the real pipeline (build_exposure_cells(), then left_join()ed back by
# cell), and reproduces main.R's two feols calls verbatim (main.R:174-188) so a future edit to
# the real formulas that isn't mirrored here will visibly diverge.

make_ddd_panel <- function(delta = -2) {
  cells <- expand.grid(
    gilnk = 3:4, moch = 1:2, teuda = c("X", "Y"),
    KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE
  )

  # Pre-period (2017-2019, Muasak == 1) rows -- one distinct occupation per demographic cell, so
  # build_exposure_cells() gives each cell a different WFH_Exposure once joined to a crosswalk
  # with varying tele_ext, exactly as main.R:152-155 does.
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

  # Post-period-spanning panel: 20 person-rows per demographic cell, Mother/Post fully crossed
  # (5 reps of the 2x2), independently-varying controls.
  make_block <- function(gilnk, moch, teuda) {
    tibble::tibble(
      Min = 2, GilNK = gilnk, TeudaGvoha = teuda, MachozMegurim = moch,
      MatzavMishpachti = factor(rep(c("A", "B"), length.out = 20)),
      Dat               = factor(rep(c("A", "B", "B", "A"), length.out = 20)),
      Mother = rep(c(0, 1, 0, 1), length.out = 20),
      Post   = rep(c(0, 0, 1, 1), length.out = 20)
    )
  }
  panel <- purrr::pmap_dfr(cells, function(gilnk, moch, teuda) make_block(gilnk, moch, teuda))

  panel %>%
    dplyr::left_join(exposure_cells, by = c("Min", "GilNK", "TeudaGvoha", "MachozMegurim")) %>%
    dplyr::mutate(
      p = plogis(-0.2 + 0.3 * Mother + 0.2 * Post + delta * Mother * Post * WFH_Exposure),
      Employed = rbinom(dplyr::n(), 1, p),
      IDPUF = dplyr::row_number()
    )
}

fit_primary_ddd <- function(ddd_df) {
  cell_fe_vars   <- c("GilNK", "TeudaGvoha", "MachozMegurim")
  other_controls <- setdiff(DEFAULT_CONTROLS, cell_fe_vars)
  cell_cluster_formula <- as.formula(paste("~", paste(cell_fe_vars, collapse = "^")))

  additive <- suppressWarnings(feols(
    as.formula(paste("Employed ~ Mother * Post * WFH_Exposure + Mother:GilNK +",
                      paste(DEFAULT_CONTROLS, collapse = " + "))),
    data = ddd_df, cluster = cell_cluster_formula
  ))
  fe <- suppressWarnings(feols(
    as.formula(paste("Employed ~ Mother * Post * WFH_Exposure + Mother:GilNK +",
                      paste(other_controls, collapse = " + "),
                      "|", paste(cell_fe_vars, collapse = "^"))),
    data = ddd_df, cluster = cell_cluster_formula
  ))
  list(additive = additive, fe = fe, cell_fe_vars = cell_fe_vars, other_controls = other_controls)
}

test_that("cell_fe_vars / other_controls split is structurally correct", {
  cell_fe_vars   <- c("GilNK", "TeudaGvoha", "MachozMegurim")
  other_controls <- setdiff(DEFAULT_CONTROLS, cell_fe_vars)

  expect_length(intersect(cell_fe_vars, other_controls), 0)
  expect_setequal(other_controls, c("MatzavMishpachti", "Dat"))
  expect_true(all(cell_fe_vars %in% DEFAULT_CONTROLS))
})

test_that("Spec 1 (additive controls) recovers the correct sign of a known injected Mother:Post:WFH_Exposure effect", {
  set.seed(42)
  panel <- make_ddd_panel(delta = -2)
  models <- fit_primary_ddd(panel)

  expect_s3_class(models$additive, "fixest")
  expect_true("WFH_Exposure" %in% names(coef(models$additive)))
  expect_true("Mother:Post:WFH_Exposure" %in% names(coef(models$additive)))
  expect_lt(unname(coef(models$additive)["Mother:Post:WFH_Exposure"]), 0)
})

test_that("Spec 2 (interacted cell FE) recovers the same sign, and fixest drops WFH_Exposure's bare main effect as collinear with the FE", {
  set.seed(42)
  panel <- make_ddd_panel(delta = -2)
  models <- fit_primary_ddd(panel)

  expect_s3_class(models$fe, "fixest")
  fe_coefs <- names(coef(models$fe))

  # The documented mechanism (main.R:164-169): WFH_Exposure is cell-constant, so its bare main
  # effect is exactly collinear with the fully interacted cell FE and fixest drops it
  # automatically -- identification of the triple interaction survives because Mother/Post still
  # vary within a cell.
  expect_false("WFH_Exposure" %in% fe_coefs)
  expect_true("Mother:Post:WFH_Exposure" %in% fe_coefs)
  expect_lt(unname(coef(models$fe)["Mother:Post:WFH_Exposure"]), 0)

  # cell_fe_vars are absorbed into the FE, not left as bare regressors.
  expect_false(any(models$cell_fe_vars %in% fe_coefs))
})
