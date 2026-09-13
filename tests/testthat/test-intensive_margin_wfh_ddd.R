# test-intensive_margin_wfh_ddd.R
# Unit tests for run_intensive_margin_wfh_ddd() (scripts/intensive_margin_wfh_ddd.R). Follows
# test-primary_ddd_mechanics.R's make_ddd_panel pattern (pre-period run through the real
# build_exposure_cells(), joined back to a post-period panel by cell), swapping the injected outcome
# from a Bernoulli Employed draw to a continuous WorkHoursCont draw with a known
# Mother:Post:WFH_Exposure effect, plus a batch of Employed==0 rows with WorkHoursCont left NA to
# confirm the Employed==1 restriction is actually enforced.

make_intensive_wfh_panel <- function(delta = -3) {
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
      Min = 2, GilNK = gilnk, TeudaGvoha = teuda, MachozMegurim = moch,
      MatzavMishpachti = factor(rep(c("A", "B"), length.out = 20)),
      Dat               = factor(rep(c("A", "B", "B", "A"), length.out = 20)),
      Mother   = rep(c(0, 1, 0, 1), length.out = 20),
      Post     = rep(c(0, 0, 1, 1), length.out = 20),
      # Period-5 dropout (not period-4, matching Post's own cycle) so Employed==0 rows land one at
      # a time across all four Mother x Post cells instead of exactly coinciding with one of them --
      # a period-4 pattern here previously emptied the Mother==1 & Post==1 cell completely once
      # filtered to Employed==1, making Mother:Post:WFH_Exposure unidentified.
      Employed = rep(c(1, 1, 1, 1, 0), length.out = 20)
    )
  }
  panel <- purrr::pmap_dfr(cells, function(gilnk, moch, teuda) make_block(gilnk, moch, teuda))

  # Join WFH_Exposure only to construct the outcome, then drop it -- run_intensive_margin_wfh_ddd()
  # does its own internal join from (cleaned_df, exposure_cells), so the panel passed to it as
  # cleaned_df must NOT already carry a WFH_Exposure column (a second join would otherwise silently
  # suffix both copies to WFH_Exposure.x/.y instead of erroring).
  joined <- panel %>%
    dplyr::left_join(exposure_cells, by = c("Min", "GilNK", "TeudaGvoha", "MachozMegurim")) %>%
    dplyr::mutate(
      WorkHoursCont = dplyr::if_else(
        Employed == 1,
        30 + 2 * Mother + 1 * Post + delta * Mother * Post * WFH_Exposure + rnorm(dplyr::n(), 0, 0.5),
        NA_real_
      ),
      IDPUF = dplyr::row_number()
    )

  list(
    panel          = dplyr::select(joined, -WFH_Exposure, -n_cell),
    exposure_cells = exposure_cells
  )
}

test_that("run_intensive_margin_wfh_ddd recovers the correct sign of a known injected effect", {
  set.seed(51)
  data <- make_intensive_wfh_panel(delta = -3)

  out <- capture.output(res <- suppressWarnings(
    run_intensive_margin_wfh_ddd(data$panel, data$exposure_cells)
  ))

  expect_s3_class(res$additive, "fixest")
  expect_true("Mother:Post:WFH_Exposure" %in% names(coef(res$additive)))
  expect_lt(unname(coef(res$additive)["Mother:Post:WFH_Exposure"]), 0)
})

test_that("run_intensive_margin_wfh_ddd restricts estimation to Employed == 1 rows", {
  set.seed(52)
  data <- make_intensive_wfh_panel()

  out <- capture.output(res <- suppressWarnings(
    run_intensive_margin_wfh_ddd(data$panel, data$exposure_cells)
  ))

  expect_equal(res$n, sum(data$panel$Employed == 1))
  expect_equal(nobs(res$additive), sum(data$panel$Employed == 1))
})

test_that("run_intensive_margin_wfh_ddd returns a printable table and both specs", {
  set.seed(53)
  data <- make_intensive_wfh_panel()

  out <- capture.output(res <- suppressWarnings(
    run_intensive_margin_wfh_ddd(data$panel, data$exposure_cells)
  ))

  expect_s3_class(res$fe, "fixest")
  expect_false("WFH_Exposure" %in% names(coef(res$fe)))  # collinear with the FE, same mechanism as the primary DDD
  expect_true("Mother:Post:WFH_Exposure" %in% names(coef(res$fe)))
})
