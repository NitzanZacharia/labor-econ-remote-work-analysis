# test-furlough_corrected_ddd.R
# Unit tests for run_basic_reg_furlough_corrected() and run_primary_ddd_furlough_corrected()
# (robustness/furlough_corrected_ddd.R).

test_that("run_basic_reg_furlough_corrected: correction shifts Mother:Post in the expected direction", {
  set.seed(31)
  n_per_cell <- 60
  panel <- purrr::map_dfr(list(c(0, 0), c(0, 1), c(1, 0), c(1, 1)), function(mp) {
    tibble::tibble(
      Mother = mp[1], Post = mp[2],
      MatzavMishpachti = factor(rep(c("A", "B"), length.out = n_per_cell)),
      Dat               = factor(rep(c("A", "B"), length.out = n_per_cell)),
      GilNK             = factor(rep(c(3, 4), length.out = n_per_cell)),
      MachozMegurim     = factor(rep(c(1, 2), length.out = n_per_cell)),
      TeudaGvoha        = factor(rep(c(1, 2), length.out = n_per_cell)),
      IDPUF = paste0(mp[1], mp[2], "_", seq_len(n_per_cell))
    )
  })
  panel$Employed <- rbinom(nrow(panel), 1, 0.8)
  # Furlough concentrated in Mother==1, Post==1 rows specifically -- reclassifies a chunk of that
  # cell's Employed==1 rows to Employed_strict==0, pulling the strict Mother:Post coefficient DOWN
  # relative to the original.
  furlough_target <- panel$Mother == 1 & panel$Post == 1 & panel$Employed == 1
  panel$Furloughed <- 0L
  panel$Furloughed[furlough_target][seq_len(sum(furlough_target) %/% 2)] <- 1L
  panel$Employed_strict <- panel$Employed - panel$Furloughed

  out <- capture.output(res <- suppressWarnings(run_basic_reg_furlough_corrected(panel)))

  expect_s3_class(res$original$models$employed, "fixest")
  expect_s3_class(res$strict$models$employed, "fixest")

  orig_coef   <- unname(coef(res$original$models$employed)["Mother:Post"])
  strict_coef <- unname(coef(res$strict$models$employed)["Mother:Post"])
  expect_lt(strict_coef, orig_coef)
})

test_that("run_primary_ddd_furlough_corrected: fits Employed_strict on the primary DDD's exact spec structure", {
  set.seed(32)
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
      MatzavMishpachti = factor(rep(c("A", "B"), length.out = 40)),
      Dat               = factor(rep(c("A", "B", "B", "A"), length.out = 40)),
      Mother = rep(c(0, 1, 0, 1), length.out = 40),
      Post   = rep(c(0, 0, 1, 1), length.out = 40)
    )
  }
  panel <- purrr::pmap_dfr(cells, function(gilnk, moch, teuda) make_block(gilnk, moch, teuda))

  joined <- panel %>%
    dplyr::left_join(exposure_cells, by = c("Min", "GilNK", "TeudaGvoha", "MachozMegurim")) %>%
    dplyr::mutate(
      p = plogis(-0.2 + 0.3 * Mother + 0.2 * Post - 2 * Mother * Post * WFH_Exposure),
      Employed = rbinom(dplyr::n(), 1, p),
      IDPUF = dplyr::row_number()
    )
  # Furlough concentrated in Post==1, low-WFH_Exposure rows (mirrors the real mechanism: low-
  # teleworkability jobs furloughed more), reclassifying half of that group's Employed==1 rows.
  low_exposure_post1 <- joined$Post == 1 & joined$WFH_Exposure < median(joined$WFH_Exposure) &
    joined$Employed == 1
  joined$Furloughed <- 0L
  joined$Furloughed[low_exposure_post1][seq_len(sum(low_exposure_post1) %/% 2)] <- 1L
  joined$Employed_strict <- joined$Employed - joined$Furloughed

  cleaned_df <- dplyr::select(joined, -WFH_Exposure, -n_cell)

  cell_fe_vars   <- c("GilNK", "TeudaGvoha", "MachozMegurim")
  other_controls <- setdiff(DEFAULT_CONTROLS, cell_fe_vars)
  cell_cluster_formula <- as.formula(paste("~", paste(cell_fe_vars, collapse = "^")))
  ddd_primary_additive <- suppressWarnings(feols(
    as.formula(paste("Employed ~ Mother * Post * WFH_Exposure + Mother:GilNK +",
                      paste(DEFAULT_CONTROLS, collapse = " + "))),
    data = joined, cluster = cell_cluster_formula
  ))
  ddd_primary_fe <- suppressWarnings(feols(
    as.formula(paste("Employed ~ Mother * Post * WFH_Exposure + Mother:GilNK +",
                      paste(other_controls, collapse = " + "),
                      "|", paste(cell_fe_vars, collapse = "^"))),
    data = joined, cluster = cell_cluster_formula
  ))

  out <- capture.output(res <- suppressWarnings(run_primary_ddd_furlough_corrected(
    cleaned_df, exposure_cells, ddd_primary_additive, ddd_primary_fe
  )))

  expect_s3_class(res$additive, "fixest")
  expect_s3_class(res$fe, "fixest")
  expect_true("Mother:Post:WFH_Exposure" %in% names(coef(res$additive)))

  orig_est   <- unname(coef(ddd_primary_additive)["Mother:Post:WFH_Exposure"])
  strict_est <- unname(coef(res$additive)["Mother:Post:WFH_Exposure"])
  expect_false(isTRUE(all.equal(orig_est, strict_est)))
})
