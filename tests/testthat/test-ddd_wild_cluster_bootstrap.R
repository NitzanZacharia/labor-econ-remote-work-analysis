# test-ddd_wild_cluster_bootstrap.R
# Smoke tests for run_wild_cluster_bootstrap() (scripts/ddd_wild_cluster_bootstrap.R). Correctness
# of the wild-cluster bootstrap algorithm itself is fwildclusterboot's responsibility, not this
# repo's -- these tests only check the wrapper's own contract: it runs on a real fitted DDD model
# with a nontrivial number of clusters and returns a p-value/CI in a sane range, and it fails
# clearly (rather than obscurely) on a bad coefficient name or a missing package. Skipped when
# fwildclusterboot isn't installed (see the package file's own header comment: it could not be
# installed in the sandbox that wrote this test, so this suite must stay green either way).

test_that("run_wild_cluster_bootstrap returns a sane p-value and CI for a real DDD model", {
  testthat::skip_if_not_installed("fwildclusterboot")
  set.seed(11)

  # More occupation clusters than test-ddd_regression.R's 3-occupation synthetic panel -- wild-
  # cluster bootstrap needs a nontrivial cluster count to be a meaningful smoke test.
  n_occ <- 20
  n_per <- 40
  panel <- purrr::map_dfr(seq_len(n_occ), function(occ) {
    ctrl <- factor(rep(c("A", "B"), length.out = n_per))
    tibble::tibble(
      Mother = rep(c(0, 1), length.out = n_per),
      Post   = rep(c(0, 0, 1, 1), length.out = n_per),
      MatzavMishpachti = ctrl, Dat = ctrl, GilNK = ctrl, MachozMegurim = ctrl, TeudaGvoha = ctrl,
      MishlachYad_ISCO_08_2 = occ,
      WFH_Exposure = occ / n_occ
    )
  })
  panel$p <- plogis(-0.5 + 0.2 * panel$Mother + 0.1 * panel$Post -
                       0.8 * panel$Mother * panel$Post * panel$WFH_Exposure)
  set.seed(12)
  panel$Employed <- rbinom(nrow(panel), 1, panel$p)

  m <- feols(
    Employed ~ Mother * Post * WFH_Exposure + MatzavMishpachti + Dat + GilNK + MachozMegurim + TeudaGvoha,
    data = panel, cluster = ~MishlachYad_ISCO_08_2
  )

  res <- run_wild_cluster_bootstrap(m, "MishlachYad_ISCO_08_2", B = 999)

  expect_true(is.numeric(res$boot_p))
  expect_gte(res$boot_p, 0)
  expect_lte(res$boot_p, 1)
  expect_true(is.numeric(res$boot_ci))
  expect_length(res$boot_ci, 2)
  expect_lt(res$boot_ci[1], res$boot_ci[2])
})

test_that("run_wild_cluster_bootstrap errors clearly if the requested coefficient doesn't exist", {
  testthat::skip_if_not_installed("fwildclusterboot")
  synth <- tibble::tibble(x = rnorm(50), grp = rep(1:10, 5), y = rnorm(50))
  m <- feols(y ~ x, data = synth, cluster = ~grp)

  expect_error(
    run_wild_cluster_bootstrap(m, "grp", param = "not_a_real_coef"),
    "not found"
  )
})

test_that("run_wild_cluster_bootstrap errors clearly when fwildclusterboot is not installed", {
  testthat::skip_if(requireNamespace("fwildclusterboot", quietly = TRUE),
                     "fwildclusterboot IS installed -- this test only covers the not-installed path")
  synth <- tibble::tibble(x = rnorm(50), grp = rep(1:10, 5), y = rnorm(50))
  m <- feols(y ~ x, data = synth, cluster = ~grp)

  expect_error(run_wild_cluster_bootstrap(m, "grp"), "not installed")
})
