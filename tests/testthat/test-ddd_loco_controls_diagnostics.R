# test-ddd_loco_controls_diagnostics.R
# Unit tests for run_ddd_leave_one_control_out() (scripts/ddd_loco_controls_diagnostics.R). Builds
# a small synthetic DDD panel directly (WFH_Exposure assigned per demographic cell, following
# test-ddd_wild_cluster_bootstrap.R's lighter-weight style rather than routing through
# build_exposure_cells(), since this function doesn't care how WFH_Exposure was constructed) and
# checks the function's own contract: one row per DEFAULT_CONTROLS-style control plus a zero-shift
# baseline row, and that dropping GilNK removes BOTH its additive term and Mother:GilNK (the
# documented special case), not just the additive term.

make_loco_panel <- function(delta = -2) {
  cells <- expand.grid(
    GilNK = 3:4, TeudaGvoha = c("X", "Y"), MachozMegurim = 1:2,
    KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE
  )
  cells$WFH_Exposure <- seq(0.1, 0.9, length.out = nrow(cells))

  panel <- purrr::pmap_dfr(cells, function(GilNK, TeudaGvoha, MachozMegurim, WFH_Exposure) {
    tibble::tibble(
      GilNK = GilNK, TeudaGvoha = TeudaGvoha, MachozMegurim = MachozMegurim,
      WFH_Exposure = WFH_Exposure,
      MatzavMishpachti = factor(rep(c("A", "B"), length.out = 40)),
      Dat               = factor(rep(c("A", "B", "B", "A"), length.out = 40)),
      Mother = rep(c(0, 1, 0, 1), length.out = 40),
      Post   = rep(c(0, 0, 1, 1), length.out = 40)
    )
  })
  panel$GilNK         <- factor(panel$GilNK)
  panel$MachozMegurim <- factor(panel$MachozMegurim)

  set.seed(7)
  p <- plogis(-0.2 + 0.3 * panel$Mother + 0.2 * panel$Post +
                delta * panel$Mother * panel$Post * panel$WFH_Exposure)
  panel$Employed <- rbinom(nrow(panel), 1, p)
  panel
}

test_that("returns one row per control plus a zero-shift baseline row", {
  set.seed(1)
  panel <- make_loco_panel()
  controls <- c("MatzavMishpachti", "Dat", "GilNK", "MachozMegurim")

  out <- capture.output(res <- suppressWarnings(
    run_ddd_leave_one_control_out(panel, controls = controls,
                                   cell_fe_vars = c("GilNK", "TeudaGvoha", "MachozMegurim"))
  ))

  expect_s3_class(res$baseline_model, "fixest")
  expect_equal(nrow(res$table), length(controls) + 1)
  expect_setequal(res$table$dropped_control, c("(none -- full baseline)", controls))

  baseline_row <- res$table[res$table$dropped_control == "(none -- full baseline)", ]
  expect_equal(baseline_row$shift_from_baseline, 0)
  expect_equal(baseline_row$shift_in_baseline_se_units, 0)
})

test_that("dropping GilNK removes both its additive term and Mother:GilNK, matching a manually fit model", {
  set.seed(2)
  panel <- make_loco_panel()
  controls <- c("MatzavMishpachti", "Dat", "GilNK", "MachozMegurim")
  cell_cluster_formula <- ~ GilNK ^ TeudaGvoha ^ MachozMegurim

  out <- capture.output(res <- suppressWarnings(
    run_ddd_leave_one_control_out(panel, controls = controls,
                                   cell_fe_vars = c("GilNK", "TeudaGvoha", "MachozMegurim"))
  ))

  manual_no_gilnk <- suppressWarnings(feols(
    Employed ~ Mother * Post * WFH_Exposure + MatzavMishpachti + Dat + MachozMegurim,
    data = panel, cluster = cell_cluster_formula
  ))

  gilnk_row <- res$table[res$table$dropped_control == "GilNK", ]
  expect_equal(
    gilnk_row$estimate,
    unname(coef(manual_no_gilnk)["Mother:Post:WFH_Exposure"]),
    tolerance = 1e-8
  )
})

test_that("every non-baseline row's estimate/se are finite and the shift columns are internally consistent", {
  set.seed(3)
  panel <- make_loco_panel()
  controls <- c("MatzavMishpachti", "Dat", "GilNK", "MachozMegurim")

  out <- capture.output(res <- suppressWarnings(
    run_ddd_leave_one_control_out(panel, controls = controls,
                                   cell_fe_vars = c("GilNK", "TeudaGvoha", "MachozMegurim"))
  ))

  tbl <- res$table
  expect_true(all(is.finite(tbl$estimate)))
  expect_true(all(is.finite(tbl$se)))
  expect_true(all(tbl$se > 0))

  baseline_est <- tbl$estimate[tbl$dropped_control == "(none -- full baseline)"]
  baseline_se  <- tbl$se[tbl$dropped_control == "(none -- full baseline)"]
  expect_equal(tbl$shift_from_baseline, tbl$estimate - baseline_est, tolerance = 1e-8)
  expect_equal(tbl$shift_in_baseline_se_units, tbl$shift_from_baseline / baseline_se, tolerance = 1e-8)
})
