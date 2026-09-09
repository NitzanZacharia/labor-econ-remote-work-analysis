# ddd_regression.R
# Checkpoint 7 (docs/ROADMAP.md): the Triple-Differences mechanism test (research doc Part 2 §2 /
# Part 4 §4), testing whether the narrowing of the motherhood penalty is actually driven by an
# occupation's WFH exposure. Depends on Checkpoint 6's build_wfh_exposure_index().
library(tidyverse)
library(fixest)
source("data_processing.R")
source("basic_regression.R")

run_ddd_regression <- function(cleaned_df, exposure_index, controls = DEFAULT_CONTROLS) {

  # ── Model 1: triple-interaction DDD ─────────────────────────────────────────
  # Attach each row's occupation-level WFH exposure by joining on the occupation code.
  df_ddd <- cleaned_df %>%
    inner_join(
      exposure_index %>% select(MishlachYad_ISCO_08_2 = occupation_code, WFH_Exposure = wfh_exposure),
      by = "MishlachYad_ISCO_08_2"
    )

  rhs_ddd <- paste(
    "Mother*Post*WFH_Exposure",
    paste(controls, collapse = " + "),
    sep = " + "
  )
  formula_ddd <- as.formula(paste("Employed ~", rhs_ddd))
  reg_ddd <- feols(formula_ddd, data = df_ddd, cluster = ~IDPUF)

  table_ddd <- etable(reg_ddd, headers = c("Employed (DDD)"), digits = 4)
  print(table_ddd)

  # ── Model 2: second-stage mechanism regression ──────────────────────────────
  # For each occupation in exposure_index, run basic_reg() on that occupation's subset of df_ddd
  # and extract its Mother:Post estimate (beta_j) AND its cluster-robust standard error (se_j).
  # Occupations with too little data for basic_reg() to fit (e.g. very small n) are dropped from
  # the mechanism regression rather than erroring the whole function.
  #
  # beta_j's precision varies enormously across occupations (subsample sizes range from the
  # min-viable-fit floor up to tens of thousands of rows), so treating every beta_j as equally
  # informative in an unweighted lm() lets noisy, small-n occupations distort the fitted
  # exposure-mechanism slope as much as large, precisely-estimated ones. reg_mechanism is
  # therefore a standard inverse-variance-weighted (precision-weighted) second-stage regression --
  # each occupation is weighted by 1/se_j^2, the usual approach for a two-step meta-regression on
  # generated regressands.
  occ_stats <- bind_rows(lapply(exposure_index$occupation_code, function(code) {
    df_occ <- filter(df_ddd, MishlachYad_ISCO_08_2 == code)
    fit <- tryCatch({
      out <- capture.output(res <- suppressWarnings(basic_reg(df_occ)))
      res
    }, error = function(e) NULL)
    if (is.null(fit) || !"Mother:Post" %in% names(coef(fit$models$employed))) {
      return(tibble(occupation_code = code, beta_j = NA_real_, se_j = NA_real_))
    }
    m <- fit$models$employed
    tibble(
      occupation_code = code,
      beta_j = unname(coef(m)[["Mother:Post"]]),
      se_j   = unname(se(m)[["Mother:Post"]])
    )
  }))

  mechanism_df <- exposure_index %>%
    left_join(occ_stats, by = "occupation_code") %>%
    # se_j > 0 (not just !is.na()) guards against a degenerate fit reporting a zero SE, which
    # would otherwise produce an infinite weight below.
    filter(!is.na(beta_j), !is.na(se_j), se_j > 0)

  n_dropped <- nrow(exposure_index) - nrow(mechanism_df)
  if (n_dropped > 0) {
    message(n_dropped, " of ", nrow(exposure_index), " occupation(s) dropped from the mechanism ",
            "regression (Mother:Post or its SE could not be estimated -- insufficient data or a ",
            "degenerate fit).")
  }

  reg_mechanism <- lm(beta_j ~ wfh_exposure, data = mechanism_df, weights = 1 / se_j^2)
  print(summary(reg_mechanism))

  return(invisible(list(
    table          = table_ddd,
    models         = list(ddd = reg_ddd, mechanism = reg_mechanism),
    mechanism_data = mechanism_df
  )))
}