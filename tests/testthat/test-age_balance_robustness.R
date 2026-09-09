# test-age_balance_robustness.R
# Unit tests for age_balance_robustness.R (Phase 1b follow-up). Uses a dedicated synthetic panel
# with a known, deliberately-injected GilNK imbalance concentrated in low-exposure cells (mirrors
# what Phase 1b found on the real data), plus a synthetic exposure_cells table -- never touches
# the real CSV or load_and_clean_data() fixtures, consistent with test-balance_test.R's convention.

make_age_panel <- function() {
  set.seed(99)
  cell_defs <- expand.grid(gilnk = 3:7, moch = 1:2, teuda = c("X", "Y"), KEEP.OUT.ATTRS = FALSE)
  cell_defs$WFH_Exposure_cell <- stats::runif(nrow(cell_defs))

  exposure_cells <- tibble::tibble(
    Min = 2, GilNK = factor(cell_defs$gilnk), TeudaGvoha = cell_defs$teuda,
    MachozMegurim = factor(cell_defs$moch), WFH_Exposure = cell_defs$WFH_Exposure_cell
  )

  panel <- purrr::pmap_dfr(cell_defs, function(gilnk, moch, teuda, WFH_Exposure_cell) {
    n <- 200
    # Young mothers over-represented in low-exposure cells, old mothers in high-exposure cells --
    # a deliberate, known imbalance concentrated at one end, mirroring the real-data finding.
    p_young_mother <- if (WFH_Exposure_cell < 0.5) 0.7 else 0.3
    tibble::tibble(
      Min = 2, GilNK = factor(gilnk), TeudaGvoha = teuda, MachozMegurim = factor(moch),
      MatzavMishpachti = factor(rep(c("A", "B"), length.out = n)),
      Dat = factor(rep(c("A", "B"), length.out = n)),
      Mother = stats::rbinom(n, 1, if (gilnk <= 4) p_young_mother else (1 - p_young_mother)),
      ShnatSeker = sample(c(2018, 2022), n, replace = TRUE)
    )
  })

  # Deliberately does NOT join exposure_cells onto panel here -- every function under test does
  # its own left_join(cleaned_df, exposure_cells, ...) internally (matching how main.R's cleaned_df
  # has no WFH_Exposure column before that join happens), so pre-joining it here would create a
  # WFH_Exposure.x/.y collision on the second join.
  panel <- panel %>%
    dplyr::mutate(
      Post = as.integer(ShnatSeker >= 2021),
      IDPUF = dplyr::row_number(),
      Employed = stats::rbinom(dplyr::n(), 1, 0.5)
    )

  list(panel = panel, exposure_cells = exposure_cells)
}

test_that("compute_pre_period_quartile_breaks + assign_wfh_quartile give consistent bins pre- and full-period", {
  d <- make_age_panel()
  breaks <- compute_pre_period_quartile_breaks(d$panel, d$exposure_cells)
  expect_length(breaks, 5)
  expect_false(any(duplicated(breaks)))

  joined <- d$panel %>% dplyr::left_join(d$exposure_cells, by = c("Min", "GilNK", "TeudaGvoha", "MachozMegurim"))
  pre  <- joined %>% dplyr::filter(ShnatSeker < 2020, !is.na(WFH_Exposure)) %>% assign_wfh_quartile(breaks)
  full <- joined %>% dplyr::filter(!is.na(WFH_Exposure)) %>% assign_wfh_quartile(breaks)
  expect_true(all(pre$WFH_Exposure_Q %in% 1:4))
  expect_true(all(full$WFH_Exposure_Q %in% 1:4))
  # A pre-period row's quartile assignment must be identical whether computed via the pre-only
  # frame or the full frame, since both use the same breakpoints.
  check <- pre %>% dplyr::select(IDPUF, WFH_Exposure_Q) %>%
    dplyr::inner_join(full %>% dplyr::select(IDPUF, WFH_Exposure_Q), by = "IDPUF", suffix = c("_pre", "_full"))
  expect_true(all(check$WFH_Exposure_Q_pre == check$WFH_Exposure_Q_full))
})

test_that("compute_pre_period_quartile_breaks errors clearly on duplicate breakpoints", {
  d <- make_age_panel()
  # Collapse every cell's WFH_Exposure to the same constant -> the pre-period distribution (after
  # the internal join) is a single value, so quantile() produces duplicate breakpoints.
  degenerate_cells <- d$exposure_cells
  degenerate_cells$WFH_Exposure <- 0.5
  expect_error(compute_pre_period_quartile_breaks(d$panel, degenerate_cells), "duplicate")
})

test_that("diagnose_gilnk_by_quartile recovers the known injected imbalance pattern", {
  d <- make_age_panel()
  out <- capture.output(res <- diagnose_gilnk_by_quartile(d$panel, d$exposure_cells))

  expect_true(all(c("gap_by_quartile", "breaks", "pre_df") %in% names(res)))
  expect_equal(nrow(res$gap_by_quartile), 4)
  # Quartile 1 (lowest exposure) was built with young mothers over-represented -> negative gap
  # (Mother1 younger than Mother0, i.e. a lower mean GilNK code).
  q1 <- dplyr::filter(res$gap_by_quartile, WFH_Exposure_Q == 1)
  expect_lt(q1$gap_Mother1_minus_0, 0)
})

test_that("run_ddd_age_interacted fits both specs and includes Mother:GilNK terms", {
  d <- make_age_panel()
  out <- capture.output(res <- run_ddd_age_interacted(
    d$panel, d$exposure_cells,
    controls = c("MatzavMishpachti", "Dat", "GilNK", "MachozMegurim")
  ))
  expect_s3_class(res$additive, "fixest")
  expect_s3_class(res$fe, "fixest")
  expect_true(any(grepl("^Mother:GilNK", names(coef(res$additive)))))
  expect_true(any(grepl("^Mother:GilNK", names(coef(res$fe)))))
})

test_that("build_gilnk_rake_weights produces weights that exactly reproduce the target GilNK distribution", {
  d <- make_age_panel()
  out <- capture.output(rake <- build_gilnk_rake_weights(d$panel, d$exposure_cells))

  pre_df <- d$panel %>%
    dplyr::left_join(d$exposure_cells, by = c("Min", "GilNK", "TeudaGvoha", "MachozMegurim")) %>%
    dplyr::filter(ShnatSeker < 2020, !is.na(WFH_Exposure)) %>%
    assign_wfh_quartile(rake$breaks)

  target <- pre_df %>% dplyr::count(WFH_Exposure_Q, GilNK, name = "n_target") %>%
    dplyr::group_by(WFH_Exposure_Q) %>% dplyr::mutate(p_target = n_target / sum(n_target)) %>%
    dplyr::ungroup()

  weighted_check <- pre_df %>%
    dplyr::left_join(rake$weights, by = c("WFH_Exposure_Q", "Mother", "GilNK")) %>%
    dplyr::group_by(WFH_Exposure_Q, Mother, GilNK) %>%
    dplyr::summarise(w_n = sum(rake_weight), .groups = "drop") %>%
    dplyr::group_by(WFH_Exposure_Q, Mother) %>%
    dplyr::mutate(w_share = w_n / sum(w_n)) %>%
    dplyr::ungroup() %>%
    dplyr::left_join(target %>% dplyr::select(WFH_Exposure_Q, GilNK, p_target),
                      by = c("WFH_Exposure_Q", "GilNK"))

  expect_equal(weighted_check$w_share, weighted_check$p_target, tolerance = 1e-10)
})

test_that("run_ddd_reweighted fits both specs using the raking weights", {
  d <- make_age_panel()
  out <- capture.output(res <- run_ddd_reweighted(
    d$panel, d$exposure_cells,
    controls = c("MatzavMishpachti", "Dat", "GilNK", "MachozMegurim")
  ))
  expect_s3_class(res$additive, "fixest")
  expect_s3_class(res$fe, "fixest")
  expect_true("Mother:Post:WFH_Exposure" %in% names(coef(res$additive)))
  expect_true("Mother:Post:WFH_Exposure" %in% names(coef(res$fe)))
})
