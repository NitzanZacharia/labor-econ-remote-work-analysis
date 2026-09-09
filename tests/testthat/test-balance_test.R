# test-balance_test.R
# Unit tests for run_balance_test() (Phase 1b). Uses a synthetic pre-period panel + a synthetic
# exposure_cells table passed in directly (mirrors test-wfh_exposure_cells.R's convention of
# testing against hand-built exposure tibbles rather than the real external CSV), so these tests
# never touch the real israeli_cbs_wfh_2digit.csv or depend on the working directory.

make_balance_panel <- function() {
  set.seed(11)
  n <- 400
  tibble::tibble(
    Min = 2, ShnatSeker = 2018,
    Mother = sample(0:1, n, replace = TRUE),
    GilNK = factor(sample(3:7, n, replace = TRUE)),
    MatzavMishpachti = factor(sample(1:5, n, replace = TRUE)),
    Dat = factor(sample(1:5, n, replace = TRUE)),
    MachozMegurim = factor(sample(1:7, n, replace = TRUE)),
    TeudaGvoha = factor(sample(c("A", "B", "C"), n, replace = TRUE))
  )
}

make_balance_cells <- function(panel) {
  # One WFH_Exposure value per distinct (GilNK, TeudaGvoha, MachozMegurim) combination present in
  # the panel, so every row matches -- keeps the test focused on run_balance_test()'s own logic
  # (quartile cut, t-test, chi-square), not on join coverage (already covered by
  # test-wfh_exposure_cells.R's build_exposure_cells() tests).
  panel %>%
    dplyr::distinct(GilNK, TeudaGvoha, MachozMegurim) %>%
    dplyr::mutate(Min = 2, WFH_Exposure = stats::runif(dplyr::n()))
}

test_that("run_balance_test returns the documented structure and every row gets a quartile", {
  panel <- make_balance_panel()
  cells <- make_balance_cells(panel)

  out <- capture.output(res <- run_balance_test(panel, exposure_cells = cells))

  expect_type(res, "list")
  expect_true(all(c("pre_df", "gilnk_balance", "gilnk_ttests", "cat_distributions", "cat_chisq") %in% names(res)))
  expect_equal(nrow(res$pre_df), nrow(panel))  # every row matched (see make_balance_cells())
  expect_true(all(res$pre_df$WFH_Exposure_Q %in% 1:4))
})

test_that("run_balance_test excludes post-2020 rows from the balance table", {
  panel <- make_balance_panel()
  panel$ShnatSeker[1:50] <- 2022
  cells <- make_balance_cells(panel)

  out <- capture.output(res <- run_balance_test(panel, exposure_cells = cells))

  expect_equal(nrow(res$pre_df), nrow(panel) - 50)
})

test_that("gilnk_ttests: mean_diff and t_stat always agree in sign (Mother1-minus-0 convention)", {
  panel <- make_balance_panel()
  cells <- make_balance_cells(panel)

  out <- capture.output(res <- run_balance_test(panel, exposure_cells = cells))

  tt <- res$gilnk_ttests
  # Where the difference is (numerically) non-zero, the reported t-statistic must have the same
  # sign as the reported mean difference -- both are documented as "Mother1 minus Mother0".
  nonzero <- abs(tt$mean_diff_Mother1_minus_0) > 1e-8
  expect_true(all(sign(tt$mean_diff_Mother1_minus_0[nonzero]) == sign(tt$t_stat_Mother1_minus_0[nonzero])))
})

test_that("run_balance_test errors clearly when no exposure input and no CSV are available", {
  panel <- make_balance_panel()
  expect_error(
    run_balance_test(panel, exposure_csv_path = "does_not_exist.csv"),
    "not found"
  )
})
