#ddd_regression
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
  # and extract its Mother:Post estimate (beta_j). Occupations with too little data for basic_reg()
  # to fit (e.g. very small n -- see the sample-size spread already flagged in Checkpoint 6) are
  # dropped from the mechanism regression rather than erroring the whole function; how many and
  # which are reported, not silently discarded.
  beta_j <- vapply(exposure_index$occupation_code, function(code) {
    df_occ <- filter(df_ddd, MishlachYad_ISCO_08_2 == code)
    fit <- tryCatch({
      out <- capture.output(res <- suppressWarnings(basic_reg(df_occ)))
      res
    }, error = function(e) NULL)
    if (is.null(fit)) return(NA_real_)
    co <- coef(fit$models$employed)
    if (!"Mother:Post" %in% names(co)) return(NA_real_)
    unname(co[["Mother:Post"]])
  }, numeric(1))

  mechanism_df <- exposure_index %>%
    mutate(beta_j = beta_j) %>%
    filter(!is.na(beta_j))

  n_dropped <- nrow(exposure_index) - nrow(mechanism_df)
  if (n_dropped > 0) {
    message(n_dropped, " of ", nrow(exposure_index), " occupation(s) dropped from the mechanism ",
            "regression (Mother:Post could not be estimated -- insufficient data or a degenerate fit).")
  }

  reg_mechanism <- lm(beta_j ~ wfh_exposure, data = mechanism_df)
  print(summary(reg_mechanism))

  return(invisible(list(
    table          = table_ddd,
    models         = list(ddd = reg_ddd, mechanism = reg_mechanism),
    mechanism_data = mechanism_df
  )))
}
