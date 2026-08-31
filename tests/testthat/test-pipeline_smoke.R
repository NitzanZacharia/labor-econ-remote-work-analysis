# test-pipeline_smoke.R
# Priority 4 / TESTING_BLUEPRINT.md §4: main.R can't be unit-tested directly (it's a script, not a
# function -- rm(list=ls()), a hardcoded path, saveRDS/readRDS caching). This mirrors its actual
# sequence against the fixtures instead: load -> comparative stats -> pooled regression ->
# Jewish/Arab stratified regressions -> child-age descriptives -> diagnostics.

test_that("the full pipeline runs end-to-end against fixtures without error, mirroring main.R's sequence", {
  cleaned <- load_and_clean_data(fixtures_dir)
  expect_gt(nrow(cleaned), 0)

  out <- capture.output(comp_res <- run_comparative_stats(cleaned))
  expect_type(comp_res, "list")

  out <- capture.output(reg_res <- basic_reg(cleaned))
  expect_s3_class(reg_res$models$employed, "fixest")

  out <- capture.output(jewish_res <- suppressWarnings(basic_reg(dplyr::filter(cleaned, Leom == 1))))
  expect_s3_class(jewish_res$models$employed, "fixest")

  out <- capture.output(arab_res <- suppressWarnings(basic_reg(dplyr::filter(cleaned, Leom == 2))))
  expect_s3_class(arab_res$models$employed, "fixest")

  out <- capture.output(age_res <- employment_by_child_age(cleaned))
  expect_s3_class(age_res$model, "fixest")

  with_null_device({
    out <- capture.output(diag_res <- run_diagnostics(cleaned))
  })
  expect_s3_class(diag_res$pretrend_model, "fixest")
})
