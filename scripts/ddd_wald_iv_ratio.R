# ddd_wald_iv_ratio.R
# Rescales the primary DDD's reduced-form Mother:Post:WFH_Exposure coefficient by the WFH-Exposure
# first stage (check_wfh_first_stage_relevance()'s level_reg: WFH_Exposure -> WFH_RefWeek, Post==1
# only) to express the null result in a more interpretable unit: the implied employment-probability
# effect per one-unit increase in a mother's actual, realized WFH-taking probability, rather than
# per unit of the diluted, cell-level exposure regressor.
#
# This is deliberately NOT a row-level 2SLS. WFH_RefWeek (data_processing.R's WFH block) is only
# non-missing for Post==1, Employed==1, AND AvadBeshavua==1 (actually worked the reference week)
# rows -- using it as an endogenous regressor with Employed as the outcome would restrict the
# estimation sample to rows where Employed is definitionally 1, leaving no outcome variation to
# explain. Dividing the two ALREADY-FITTED coefficients (a Wald/IV ratio) sidesteps that degenerate
# sample entirely.
#
# Framing: this is a reinterpretation of MAGNITUDE (economic significance), not a fix for
# STATISTICAL significance. The delta-method SE below will generally not shrink the p-value below
# the reduced form's own -- dividing both point estimate and SE by the same first-stage coefficient
# leaves the t-statistic roughly unchanged before accounting for the first stage's own sampling
# uncertainty, and accounting for that (via the delta method) can only add variance, not remove it.
#
# The delta-method SE also assumes the reduced-form and first-stage models' sampling errors are
# independent. They are not exactly: the reduced-form model's sample spans Post==0 and Post==1,
# while the first-stage model is estimated on the Post==1 subset of (approximately) that same
# population -- so this is an approximation, not an exact result, in the same spirit as
# ddd_exposure_synthesis.R's "ANTI-CONSERVATIVE" caveat for its own naive pooled SE.
library(fixest)

compute_ddd_wald_iv_ratio <- function(reduced_form_model, first_stage_model,
                                       rf_coef_name = "Mother:Post:WFH_Exposure",
                                       fs_coef_name = "WFH_Exposure") {
  rf_se_vec <- fixest::se(reduced_form_model)
  fs_se_vec <- fixest::se(first_stage_model)

  if (!rf_coef_name %in% names(rf_se_vec) || is.na(rf_se_vec[[rf_coef_name]])) {
    stop(sprintf(
      "compute_ddd_wald_iv_ratio: '%s' not found (or NA/dropped) in reduced_form_model.",
      rf_coef_name
    ))
  }
  if (!fs_coef_name %in% names(fs_se_vec) || is.na(fs_se_vec[[fs_coef_name]])) {
    stop(sprintf(
      "compute_ddd_wald_iv_ratio: '%s' not found (or NA/dropped) in first_stage_model.",
      fs_coef_name
    ))
  }

  rf_estimate <- unname(coef(reduced_form_model)[[rf_coef_name]])
  rf_se       <- unname(rf_se_vec[[rf_coef_name]])
  fs_estimate <- unname(coef(first_stage_model)[[fs_coef_name]])
  fs_se       <- unname(fs_se_vec[[fs_coef_name]])

  if (fs_estimate == 0) {
    stop("compute_ddd_wald_iv_ratio: first-stage coefficient is exactly 0 -- ratio is undefined.")
  }

  ratio_estimate <- rf_estimate / fs_estimate
  ratio_se <- sqrt(
    rf_se^2 / fs_estimate^2 +
      (rf_estimate^2 * fs_se^2) / fs_estimate^4
  )
  z <- ratio_estimate / ratio_se
  p <- 2 * (1 - pnorm(abs(z)))

  interpretation <- sprintf(
    paste0(
      "Implied effect on employment probability of a mother moving from 0%% to 100%% realized ",
      "WFH-taking probability (rescaling %s by the WFH_Exposure -> WFH_RefWeek first stage): ",
      "%.4f (delta-method SE %.4f, z = %.3f, p = %.4f). This rescales magnitude/interpretability -- ",
      "it is not evidence the underlying effect is more precisely estimated than the reduced form."
    ),
    rf_coef_name, ratio_estimate, ratio_se, z, p
  )
  message(interpretation)

  invisible(list(
    rf_estimate    = rf_estimate,
    rf_se          = rf_se,
    fs_estimate    = fs_estimate,
    fs_se          = fs_se,
    ratio_estimate = ratio_estimate,
    ratio_se       = ratio_se,
    z              = z,
    p              = p,
    interpretation = interpretation
  ))
}
