# test-mother_heterogeneity_robustness.R
# Unit tests for run_ddd_by_child_age() and run_ddd_by_single_parent()
# (robustness/mother_heterogeneity_robustness.R). Follows test-primary_ddd_mechanics.R's
# make_ddd_panel pattern, adding GilYeledTzairMBNK (youngest-child-age code) and
# MisparHorimYechidim (single-parent count, per the file's own stated >0 assumption) columns, with
# non-mothers coded 0 on both (mirroring GilYeledTzairMBNK's real "0 = no children" convention).

make_heterogeneity_panel <- function(delta_young = -4, delta_old = 0) {
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

  # 40 rows/cell: 20 non-mothers, 10 mothers of a young child (GilYeledTzairMBNK 1-2), 10 mothers of
  # an older child (3-5). Half of each mother sub-block is a single parent (MisparHorimYechidim = 1).
  make_block <- function(gilnk, moch, teuda) {
    tibble::tibble(
      Min = 2, GilNK = gilnk, TeudaGvoha = teuda, MachozMegurim = moch,
      MatzavMishpachti = factor(rep(c("A", "B"), length.out = 40)),
      Dat               = factor(rep(c("A", "B", "B", "A"), length.out = 40)),
      Mother = rep(c(0, 1), c(20, 20)),
      Post   = rep(c(0, 0, 1, 1), length.out = 40),
      # Period-2 alternation (not period-4, like Post's own cycle) so young/old and Post stay
      # independent within the mother block -- a period-4 assignment here previously locked every
      # young-coded row to Post==0 and every old-coded row to Post==1 (both cycles shared the same
      # phase), making Mother:Post:WFH_Exposure identically zero within each subgroup.
      GilYeledTzairMBNK    = c(rep(0, 20), rep(c(1, 4), 10)),
      MisparHorimYechidim  = c(rep(0, 20), rep(c(0, 1), 10))
    )
  }
  panel <- purrr::pmap_dfr(cells, function(gilnk, moch, teuda) make_block(gilnk, moch, teuda))

  # Join WFH_Exposure only to construct Employed, then drop it -- run_ddd_by_child_age()/
  # run_ddd_by_single_parent() do their own internal join from (cleaned_df, exposure_cells), so the
  # panel passed to them must NOT already carry a WFH_Exposure column (a second join would otherwise
  # silently suffix both copies to WFH_Exposure.x/.y instead of erroring).
  joined <- panel %>%
    dplyr::left_join(exposure_cells, by = c("Min", "GilNK", "TeudaGvoha", "MachozMegurim")) %>%
    dplyr::mutate(
      is_young = Mother == 1 & GilYeledTzairMBNK %in% 1:2,
      p = plogis(-0.2 + 0.3 * Mother + 0.2 * Post +
                   dplyr::if_else(is_young, delta_young, delta_old) * Mother * Post * WFH_Exposure),
      Employed = rbinom(dplyr::n(), 1, p),
      IDPUF = dplyr::row_number()
    )

  list(
    panel          = dplyr::select(joined, -WFH_Exposure, -n_cell),
    exposure_cells = exposure_cells
  )
}

test_that("run_ddd_by_child_age splits mothers correctly and both non-mother comparison groups match", {
  set.seed(61)
  data <- make_heterogeneity_panel()

  out <- capture.output(res <- suppressWarnings(run_ddd_by_child_age(data$panel, data$exposure_cells)))

  expect_equal(res$young$n, sum(data$panel$Mother == 0) +
                 sum(data$panel$Mother == 1 & data$panel$GilYeledTzairMBNK %in% 1:2))
  expect_equal(res$older$n, sum(data$panel$Mother == 0) +
                 sum(data$panel$Mother == 1 & data$panel$GilYeledTzairMBNK %in% 3:5))
})

test_that("run_ddd_by_child_age recovers a larger-magnitude effect in the subgroup it was injected into", {
  set.seed(62)
  data <- make_heterogeneity_panel(delta_young = -6, delta_old = 0)

  out <- capture.output(res <- suppressWarnings(run_ddd_by_child_age(data$panel, data$exposure_cells)))

  young_est <- unname(coef(res$young$additive)["Mother:Post:WFH_Exposure"])
  older_est <- unname(coef(res$older$additive)["Mother:Post:WFH_Exposure"])
  expect_lt(young_est, older_est)
})

test_that("run_ddd_by_child_age returns an MDE table with the documented fields for every spec", {
  set.seed(63)
  data <- make_heterogeneity_panel()

  out <- capture.output(res <- suppressWarnings(run_ddd_by_child_age(data$panel, data$exposure_cells)))

  expect_setequal(names(res$mde_table), c("spec", "point_estimate", "se", "mde", "within_mde"))
  expect_equal(nrow(res$mde_table), 4)
  expect_true(all(res$mde_table$mde > 0))
})

test_that("run_ddd_by_single_parent splits mothers on MisparHorimYechidim > 0 and comparison groups match", {
  set.seed(64)
  data <- make_heterogeneity_panel()

  out <- capture.output(res <- suppressWarnings(run_ddd_by_single_parent(data$panel, data$exposure_cells)))

  n_single     <- sum(data$panel$Mother == 1 & data$panel$MisparHorimYechidim > 0)
  n_partnered  <- sum(data$panel$Mother == 1 & data$panel$MisparHorimYechidim == 0)
  n_non_mother <- sum(data$panel$Mother == 0)

  expect_equal(res$single$n, n_non_mother + n_single)
  expect_equal(res$partnered$n, n_non_mother + n_partnered)
})
