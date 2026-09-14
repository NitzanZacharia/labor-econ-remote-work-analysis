# furlough_diagnostics.R
# Real-data verification for the Furloughed/Employed_strict correction (data_processing.R's
# derivation comment, docs/decisions/furlough-employed-contamination.md). Three checks:
#   (a) furlough rate (SibaNeedar==9 among Muasak==1) by year -- reproduces the codebook-grounded
#       real-data pattern (stable ~0.1-0.35% pre-period, spikes in 2021/2023) directly from
#       whatever data is actually passed in, so it can't silently go stale.
#   (b) a consistency check that SibaNeedar is populated only when AvadBeshavua==4 (the codebook's
#       "asked only when the reference-week work question was answered 'no'" claim) -- mirrors
#       validation.R's check_wfh_refweek_avadbeshavua() in spirit and reporting style.
#   (c) furlough rate by Post x Mother x WFH_Exposure quartile -- the actual DDD-relevant mechanism
#       check: does furlough incidence concentrate in low-exposure cells and/or differ by Mother,
#       the pattern needed to explain attenuation of Mother:Post:WFH_Exposure toward zero, not just
#       a level shift in Employed.
#
# Report-only, tolerant of missing inputs (mirrors check_wfh_refweek_avadbeshavua()'s degrade-
# gracefully-with-a-message convention rather than erroring). Deliberately does NOT depend on
# robustness/age_balance_robustness.R's quartile-cutting functions -- this file stays in scripts/,
# and the codebase's existing dependency direction is robustness/ -> scripts/, never the reverse --
# so the caller (main.R) is expected to build df_with_quartile itself using those functions and pass
# the result in.
library(tidyverse)

check_furlough_incidence <- function(cleaned_df, df_with_quartile = NULL) {

  # (a) Furlough rate by year, among Muasak==1 rows.
  by_year <- cleaned_df %>%
    filter(Muasak == 1) %>%
    group_by(ShnatSeker) %>%
    summarise(n_employed = n(), n_furloughed = sum(Furloughed),
              rate = 100 * n_furloughed / n_employed, .groups = "drop")
  message("=== Furlough rate (SibaNeedar==9 among Muasak==1), by year ===")
  print(by_year)

  # (b) Consistency: SibaNeedar populated only when AvadBeshavua==4.
  if (!"AvadBeshavua" %in% names(cleaned_df)) {
    message("check_furlough_incidence: 'AvadBeshavua' is not present in cleaned_df -- the ",
            "'SibaNeedar asked only when AvadBeshavua==4' claim cannot be verified against this data.")
    consistency <- list(available = FALSE)
  } else {
    populated <- cleaned_df %>% filter(!is.na(SibaNeedar))
    n <- nrow(populated)
    if (n == 0) {
      message("check_furlough_incidence: no rows with SibaNeedar populated were found -- nothing ",
              "to check for consistency.")
      consistency <- list(available = TRUE, n = 0)
    } else {
      consistent    <- sum(populated$AvadBeshavua == 4, na.rm = TRUE)
      inconsistent  <- sum(populated$AvadBeshavua != 4, na.rm = TRUE)
      indeterminate <- sum(is.na(populated$AvadBeshavua))
      message(sprintf(
        paste0(
          "check_furlough_incidence: of %d row(s) with SibaNeedar populated, %d (%.1f%%) have ",
          "AvadBeshavua==4 (consistent), %d (%.1f%%) do not (INCONSISTENT), %d (%.1f%%) ",
          "indeterminate (AvadBeshavua itself missing)."
        ),
        n, consistent, 100 * consistent / n, inconsistent, 100 * inconsistent / n,
        indeterminate, 100 * indeterminate / n
      ))
      if (inconsistent > 0) {
        warning(sprintf(
          paste0(
            "check_furlough_incidence: SibaNeedar is populated for %d row(s) where AvadBeshavua != ",
            "4 -- the codebook's 'asked only when AvadBeshavua==4' assumption may not fully hold; ",
            "review before relying on it."
          ),
          inconsistent
        ))
      }
      consistency <- list(available = TRUE, n = n, consistent = consistent,
                           inconsistent = inconsistent, indeterminate = indeterminate)
    }
  }

  # (c) Furlough rate by Post x Mother x WFH_Exposure quartile -- the mechanism check.
  by_quartile <- NULL
  if (is.null(df_with_quartile)) {
    message("check_furlough_incidence: no quartile-assigned data supplied -- skipping the Post x ",
            "Mother x WFH_Exposure quartile breakdown (part c). Pass df_with_quartile (built via ",
            "compute_pre_period_quartile_breaks()/assign_wfh_quartile()) to enable it.")
  } else if (!"WFH_Exposure_Q" %in% names(df_with_quartile)) {
    message("check_furlough_incidence: df_with_quartile has no 'WFH_Exposure_Q' column -- skipping ",
            "part c.")
  } else {
    by_quartile <- df_with_quartile %>%
      filter(Muasak == 1, !is.na(WFH_Exposure_Q)) %>%
      group_by(Post, Mother, WFH_Exposure_Q) %>%
      summarise(n_employed = n(), n_furloughed = sum(Furloughed),
                rate = 100 * n_furloughed / n_employed, .groups = "drop")
    message("=== Furlough rate by Post x Mother x WFH_Exposure quartile ===")
    print(by_quartile, n = Inf)
  }

  invisible(list(by_year = by_year, consistency = consistency, by_quartile = by_quartile))
}
