# balance_test.R
# Phase 1b: pre-period covariate balance between Mother==1 and Mother==0, checked separately
# within WFH_Exposure quartiles (built the same way as the primary DDD's cell-based exposure,
# main.R:120-128), restricted to the pre-period (ShnatSeker < 2020, i.e. 2017-2019 -- 2020 itself
# is never in the sample). A straightforward covariate-balance table, not a new modeling
# framework: GilNK is treated as an ordinal numeric code (mean + Welch t-test by Mother, per
# quartile); the remaining DEFAULT_CONTROLS (MatzavMishpachti, Dat, MachozMegurim, TeudaGvoha) are
# nominal factors, so "mean" isn't meaningful -- each is reported as a %-distribution by Mother,
# per quartile, with a chi-square test of independence.
#
# cleaned_df is expected to be the primary (women) analysis sample, matching main.R's ddd_df.
library(tidyverse)
source(file.path("scripts", "data_processing.R"))
source(file.path("scripts", "wfh_exposure_cells.R"))

run_balance_test <- function(cleaned_df, controls = DEFAULT_CONTROLS,
                              exposure_cells = NULL, exposure_calibrated = NULL,
                              exposure_csv_path = file.path("data", "israeli_cbs_wfh_2digit.csv")) {

  # Reuse whatever the caller already has -- main.R's own exposure_cells/exposure_calibrated --
  # rather than always rebuilding from the raw CSV; only fall back to a fresh build (and only then
  # require the CSV to actually exist) when nothing is supplied.
  if (is.null(exposure_cells)) {
    if (is.null(exposure_calibrated)) {
      if (!file.exists(exposure_csv_path)) {
        stop("run_balance_test: no exposure_cells/exposure_calibrated supplied and '",
             exposure_csv_path, "' not found from the current working directory. Pass one of ",
             "these explicitly (e.g. main.R's own exposure_cells/exposure_calibrated) or set ",
             "exposure_csv_path to the real file's location.")
      }
      message("Building calibrated occupation-level WFH exposure...")
      exposure_external   <- build_exposure_isco2(path = exposure_csv_path)
      exposure_calibrated <- calibrate_isco_exposure(cleaned_df, exposure_external)
    }
    message("Building cell-based WFH exposure...")
    exposure_cells <- build_exposure_cells(
      cleaned_df,
      exposure_calibrated %>% select(ISCO2, tele_ext = wfh_exposure_calibrated)
    )
  }

  pre_df <- cleaned_df %>%
    filter(ShnatSeker < 2020) %>%
    left_join(exposure_cells, by = c("Min", "GilNK", "TeudaGvoha", "MachozMegurim")) %>%
    filter(!is.na(WFH_Exposure)) %>%
    mutate(WFH_Exposure_Q = ntile(WFH_Exposure, 4))

  message(sprintf(
    "run_balance_test: %d pre-period rows with a matched exposure cell (quartiles cut on this set).",
    nrow(pre_df)
  ))

  # ── GilNK: ordinal numeric code, mean + Welch t-test by Mother, per quartile ─────────────────
  gilnk_num <- function(x) as.numeric(as.character(x))

  gilnk_balance <- pre_df %>%
    group_by(WFH_Exposure_Q, Mother) %>%
    summarise(mean_GilNK = mean(gilnk_num(GilNK), na.rm = TRUE), n = n(), .groups = "drop")

  gilnk_ttests <- pre_df %>%
    group_by(WFH_Exposure_Q) %>%
    group_modify(~ {
      tt <- t.test(gilnk_num(GilNK) ~ Mother, data = .x)
      # t.test()'s own $statistic is (mean in group 0 - mean in group 1)/se (ascending
      # factor-level order); flip its sign so it lines up with the Mother1-minus-0 direction used
      # for mean_diff below, rather than reporting the two with opposite sign conventions.
      tibble(
        mean_diff_Mother1_minus_0 = unname(tt$estimate[2] - tt$estimate[1]),
        t_stat_Mother1_minus_0    = -unname(tt$statistic),
        p_value                   = tt$p.value
      )
    }) %>%
    ungroup()

  message("=== GilNK balance: mean by Mother, per WFH_Exposure quartile ===")
  print(gilnk_balance)
  message("=== GilNK balance: Welch t-test (Mother==1 vs Mother==0), per WFH_Exposure quartile ===")
  print(gilnk_ttests)

  # ── Remaining controls: nominal factors, %-distribution by Mother + chi-square, per quartile ──
  cat_controls <- setdiff(controls, "GilNK")

  cat_distributions <- map(cat_controls, function(col) {
    pre_df %>%
      count(WFH_Exposure_Q, Mother, .data[[col]], name = "n") %>%
      group_by(WFH_Exposure_Q, Mother) %>%
      mutate(pct = 100 * n / sum(n)) %>%
      ungroup() %>%
      rename(level = !!col) %>%
      mutate(variable = col, .before = 1)
  }) %>% list_rbind()

  cat_chisq <- map(cat_controls, function(col) {
    pre_df %>%
      group_by(WFH_Exposure_Q) %>%
      group_modify(~ {
        tab  <- table(.x$Mother, .x[[col]])
        test <- suppressWarnings(chisq.test(tab))
        tibble(chisq_stat = unname(test$statistic), df = unname(test$parameter), p_value = test$p.value)
      }) %>%
      ungroup() %>%
      mutate(variable = col, .before = 1)
  }) %>% list_rbind()

  message("=== Categorical controls: % distribution by Mother, per WFH_Exposure quartile ===")
  print(cat_distributions, n = Inf)
  message("=== Categorical controls: chi-square test (Mother vs. level), per WFH_Exposure quartile ===")
  print(cat_chisq)

  invisible(list(
    pre_df            = pre_df,
    gilnk_balance     = gilnk_balance,
    gilnk_ttests      = gilnk_ttests,
    cat_distributions = cat_distributions,
    cat_chisq         = cat_chisq
  ))
}
