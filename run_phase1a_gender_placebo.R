# run_phase1a_gender_placebo.R
#
# Standalone entry point reconstructing Phase 1a's saved gender-placebo run as its own artifact.
# The original run left only csvs/phase1a_gender_placebo.rds behind -- no committed source file
# produced it. Reconstructed from the cached object's structure (list(cleaned_men, result,
# ddd_placebo), matching run_gender_placebo()'s own return value exactly) -- see
# run_mishkalsofi_check.R's header for the same provenance note applied to a different cache.
#
# run_gender_placebo() (scripts/gender_placebo.R) is self-contained: it loads/validates the male
# subsample itself and builds the calibrated occupation-level exposure from the cached women's
# data (csvs/cleaned_df.rds) plus data/israeli_cbs_wfh_2digit.csv, so this script only needs to
# call it and save the result -- no separate data-loading/caching boilerplate here.
#
# Console output only, plus the one saved artifact this script exists to reconstruct
# (csvs/phase1a_gender_placebo.rds) -- nothing written to outputs/.
#
# Rscript run_phase1a_gender_placebo.R

rm(list = ls())
source(file.path("scripts", "gender_placebo.R"))

message("Edit folder_path below if needed!")
folder_path <- "csvs"

result <- run_gender_placebo(folder_path)

saveRDS(result, file.path(folder_path, "phase1a_gender_placebo.rds"))

message("\nDone. Console output above; the results list was also saved to ",
        file.path(folder_path, "phase1a_gender_placebo.rds"),
        " -- run this past disclosure review before putting it in a draft.")
