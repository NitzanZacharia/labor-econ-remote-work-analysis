# ddd_wild_cluster_bootstrap.R
# Small-cluster correction (audit finding E3) for the ~40-ISCO-2-cluster occupation-level
# robustness DDDs (run_ddd_regression()'s Model 1, main.R's 8b-8d) -- their cluster-robust SEs
# previously got no small-cluster adjustment, unlike the already-documented (not-yet-implemented)
# follow-up flagged for the ~210-cluster primary DDD. Wild-cluster bootstrap (Cameron, Gelbach &
# Miller 2008) is the standard correction for a small number of clusters, implemented here via
# fwildclusterboot::boottest() rather than from scratch.
#
# New dependency (fwildclusterboot), flagged to and approved by the user per CLAUDE.md.
#
# IMPORTANT CAVEAT: fwildclusterboot's exact return-object field names used below ($p_val,
# $conf_int) come from the package's public documentation/vignette examples, NOT from a live
# verification in this session -- CRAN package installation was attempted here and failed because
# this sandbox could not reach a working CRAN mirror. Before relying on this function's output:
# install fwildclusterboot locally, run `Rscript run_tests.R` (test-ddd_wild_cluster_bootstrap.R
# exercises this function directly against a real fitted model), and spot-check one real call's
# output against `summary(res$boot_summary)` to confirm these field names still match the
# installed package version.
run_wild_cluster_bootstrap <- function(model, cluster_var, param = "Mother:Post:WFH_Exposure",
                                        B = 9999, seed = 1) {
  if (!requireNamespace("fwildclusterboot", quietly = TRUE)) {
    stop("run_wild_cluster_bootstrap: the 'fwildclusterboot' package is required but not ",
         "installed. Install it with install.packages('fwildclusterboot') before calling this ",
         "function.")
  }
  if (!param %in% names(fixest::coef(model))) {
    stop(sprintf(
      "run_wild_cluster_bootstrap: '%s' not found in the fitted model's coefficients -- was it dropped by collinearity?",
      param
    ))
  }

  boot <- fwildclusterboot::boottest(
    model, clustid = cluster_var, param = param, B = B, seed = seed
  )

  list(
    param             = param,
    cluster_var       = cluster_var,
    cluster_robust_se = unname(fixest::se(model)[[param]]),
    boot_p            = boot$p_val,
    boot_ci           = boot$conf_int,
    boot_summary      = boot
  )
}
