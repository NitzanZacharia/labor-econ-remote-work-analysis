# ddd_exposure_synthesis.R
# Precision-weighted (inverse-variance) synthesis of the Mother:Post:WFH_Exposure estimate across
# the primary cell-based DDD (2 specs) and the occupation-level robustness DDDs (external,
# calibrated, realized) documented in docs/decisions/calibrated-exposure-and-cell-ddd.md. Each
# model targets the same theoretical estimand -- does an occupation/cell's WFH exposure amplify
# mothers' relative employment change post-2021 -- via a different, imperfect WFH_Exposure proxy
# and a partially-overlapping sample. This is a synthesis across imperfect measures of one
# construct, not a textbook meta-analysis of independent studies, and two things follow from that:
#
#   1. The standard fixed-effect meta-analysis formula (weight = 1/se^2) assumes independent
#      sampling error across "studies". These estimates are NOT independent -- they draw on
#      overlapping respondents -- so the pooled SE below is an ANTI-CONSERVATIVE lower bound, not a
#      standalone valid inference. It's reported alongside, never instead of, each individual
#      estimate, with the single most-precise individual model's SE flagged as a conservative
#      reference ceiling.
#   2. Cochran's Q tests whether the supplied estimates are even statistically consistent with one
#      another before pooling is a sensible summary at all -- a significant Q means the
#      disagreement across measures is itself the finding, not something pooling should average
#      away silently.
library(tidyverse)
library(fixest)

synthesize_ddd_triple_interaction <- function(models, coef_name = "Mother:Post:WFH_Exposure") {
  stopifnot(!is.null(names(models)), all(nzchar(names(models))), length(models) >= 2)

  per_model_stats <- lapply(models, function(m) {
    se_vec <- fixest::se(m)
    if (!coef_name %in% names(se_vec) || is.na(se_vec[[coef_name]])) {
      stop(sprintf(
        paste0("synthesize_ddd_triple_interaction: '%s' not found (or NA/dropped by ",
               "collinearity) in one of the supplied models."),
        coef_name
      ))
    }
    tibble(estimate = unname(coef(m)[[coef_name]]), se = unname(se_vec[[coef_name]]))
  })

  per_model <- tibble(model = names(models)) %>%
    bind_cols(bind_rows(per_model_stats))

  w <- 1 / per_model$se^2
  pooled_estimate <- sum(w * per_model$estimate) / sum(w)
  pooled_se        <- sqrt(1 / sum(w))
  pooled_z         <- pooled_estimate / pooled_se
  pooled_p         <- 2 * (1 - pnorm(abs(pooled_z)))

  q_stat <- sum(w * (per_model$estimate - pooled_estimate)^2)
  q_df   <- nrow(per_model) - 1
  q_p    <- 1 - pchisq(q_stat, df = q_df)

  most_precise_idx <- which.min(per_model$se)

  message(sprintf(
    paste0(
      "=== Precision-weighted synthesis of %s across %d models ===\n",
      "%s\n",
      "Naive pooled (assumes independence -- ANTI-CONSERVATIVE, see header comment): ",
      "estimate = %.4f, SE = %.4f, z = %.3f, p = %.4f\n",
      "Cochran's Q = %.3f on %d df, p = %.4f (%s)\n",
      "Most precise individual model: '%s' (SE = %.4f) -- conservative reference ceiling"
    ),
    coef_name, nrow(per_model),
    paste(sprintf("  %-20s estimate = %8.4f, SE = %.4f", per_model$model, per_model$estimate, per_model$se),
          collapse = "\n"),
    pooled_estimate, pooled_se, pooled_z, pooled_p,
    q_stat, q_df, q_p,
    if (q_p < 0.05) "estimates are significantly heterogeneous -- pooling masks real disagreement" else "estimates are statistically consistent with a common effect",
    per_model$model[[most_precise_idx]], per_model$se[[most_precise_idx]]
  ))

  invisible(list(
    per_model           = per_model,
    pooled_estimate     = pooled_estimate,
    pooled_se           = pooled_se,
    pooled_z            = pooled_z,
    pooled_p            = pooled_p,
    q_stat              = q_stat,
    q_df                = q_df,
    q_p                 = q_p,
    heterogeneous       = q_p < 0.05,
    most_precise_model  = per_model$model[[most_precise_idx]]
  ))
}
