# test-isco_masking_diagnostics.R
# Unit tests for check_isco_masking_sensitivity(): the audit-driven proxy check comparing realized
# WFH between disclosure-masked and unmasked rows within the same ISCO1 major group. Uses a
# synthetic design where the within-group masked/unmasked gap is exactly hand-computable via FWL:
# a second, entirely-unmasked ISCO1 group is included specifically to confirm it's absorbed by the
# ISCO1 fixed effect and contributes nothing to the ISCO_masked coefficient.

make_masking_row <- function(ISCO1, ISCO_masked, WFH, ShnatSeker = 2022) {
  tibble::tibble(
    ISCO1 = ISCO1, ISCO_masked = ISCO_masked, WFH = WFH,
    Employed = 1L, ShnatSeker = ShnatSeker
  )
}

make_masking_synth <- function() {
  synth <- dplyr::bind_rows(
    make_masking_row(2, FALSE, rep(1, 10)),        # ISCO1=2, unmasked: all WFH=1
    make_masking_row(2, TRUE,  rep(0, 10)),        # ISCO1=2, masked:   all WFH=0  (gap = -1)
    make_masking_row(3, FALSE, rep(c(1, 0), 5)),   # ISCO1=3, unmasked only (no masked rows at all)
    make_masking_row(NA_real_, TRUE, 1),           # fully-masked ("XX"): ISCO1 unrecoverable
    make_masking_row(2, FALSE, 1, ShnatSeker = 2019) # wrong ref_year -- must be excluded by default
  )
  synth$IDPUF <- seq_len(nrow(synth))
  synth
}

test_that("check_isco_masking_sensitivity returns the documented structure and fits on fixture data", {
  cleaned <- load_and_clean_data(fixtures_dir)
  out <- capture.output(res <- suppressWarnings(check_isco_masking_sensitivity(cleaned)))

  expect_type(res, "list")
  expect_true(all(c("by_group", "comparison_wide", "model") %in% names(res)))
  expect_s3_class(res$model, "fixest")
})

test_that("fully-masked (ISCO1 == NA) rows are excluded entirely", {
  synth <- make_masking_synth()
  out <- capture.output(res <- suppressWarnings(check_isco_masking_sensitivity(synth)))

  expect_false(any(is.na(res$by_group$ISCO1)))
  # 10 + 10 + 10 = 30 rows total across both groups' masked/unmasked counts (the NA-ISCO1 row and
  # the wrong-ref_year row are both excluded)
  expect_equal(sum(res$by_group$n), 30)
})

test_that("rows outside ref_year are excluded by default", {
  synth <- make_masking_synth()
  out <- capture.output(res <- suppressWarnings(check_isco_masking_sensitivity(synth)))
  expect_equal(sum(res$by_group$n), 30)  # the 2019 row would make this 31 if not filtered
})

test_that("comparison_wide reports the exact masked/unmasked gap per ISCO1 group", {
  synth <- make_masking_synth()
  out <- capture.output(res <- suppressWarnings(check_isco_masking_sensitivity(synth)))

  row2 <- res$comparison_wide[res$comparison_wide$ISCO1 == 2, ]
  expect_equal(row2$mean_wfh_unmasked, 1)
  expect_equal(row2$mean_wfh_masked, 0)
  expect_equal(row2$gap, -1)

  row3 <- res$comparison_wide[res$comparison_wide$ISCO1 == 3, ]
  expect_equal(row3$mean_wfh_unmasked, 0.5)
  expect_true(is.na(row3$mean_wfh_masked))  # no masked rows at all in this group
  expect_true(is.na(row3$gap))
})

test_that("the ISCO_masked coefficient exactly recovers the within-group gap, unaffected by the all-unmasked group", {
  synth <- make_masking_synth()
  out <- capture.output(res <- suppressWarnings(check_isco_masking_sensitivity(synth)))

  # FWL: ISCO1=3 is constant on ISCO_masked (all FALSE) and is fully absorbed by the ISCO1 FE, so
  # it contributes nothing to the slope -- the coefficient must equal exactly the ISCO1=2 group's
  # own masked-vs-unmasked mean difference (0 - 1 = -1).
  co <- coef(res$model)
  expect_equal(unname(co[["ISCO_maskedTRUE"]]), -1, tolerance = 1e-8)
})
