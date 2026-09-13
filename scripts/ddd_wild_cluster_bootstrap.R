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
# fwildclusterboot was archived from CRAN; install it (and its own archived dependency,
# summclust) from GitHub: remotes::install_github("s3alfisc/summclust"), then
# remotes::install_github("s3alfisc/fwildclusterboot"). $p_val/$conf_int field names verified
# against a live boottest() call on real data (2026-09-13).
#
# boottest() dropped its own `seed` argument in fwildclusterboot 0.13 (installed here: 0.14.3) --
# reproducibility is now controlled only via the global RNG state, set below with set.seed() and
# dqrng::dqset.seed() (boottest()'s default sampling = "dqrng" draws from dqrng's own generator,
# not base R's, so both seeds are needed) rather than passed into the call.
run_wild_cluster_bootstrap <- function(model, cluster_var, param = "Mother:Post:WFH_Exposure",
                                        B = 9999, seed = 1) {
  if (!requireNamespace("fwildclusterboot", quietly = TRUE)) {
    stop("run_wild_cluster_bootstrap: the 'fwildclusterboot' package is required but not ",
         "installed. Install it with install.packages('fwildclusterboot') before calling this ",
         "function.")
  }
  if (!param %in% names(coef(model))) {
    stop(sprintf(
      "run_wild_cluster_bootstrap: '%s' not found in the fitted model's coefficients -- was it dropped by collinearity?",
      param
    ))
  }

  set.seed(seed)
  if (requireNamespace("dqrng", quietly = TRUE)) {
    dqrng::dqset.seed(seed)
  }

  boot <- fwildclusterboot::boottest(
    model, clustid = cluster_var, param = param, B = B
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
