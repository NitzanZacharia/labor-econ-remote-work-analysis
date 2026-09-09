library(tidyverse)
library(fixest)

# Function to import the external, objective teleworkability index. `path` defaults to the
# project's real data file (not present in every environment -- a known, separately-tracked gap,
# not something this default is meant to paper over); the parameter exists so callers -- and
# tests -- can point at a different file without editing this function.
build_exposure_isco2 <- function(path = file.path("data", "israeli_cbs_wfh_2digit.csv")) {
  read_csv(path, show_col_types = FALSE) %>%
    transmute(ISCO2 = as.numeric(isco_2digit), tele_ext = wfh_probability_2d) %>%
    filter(!is.na(tele_ext))
}

# Corrects the external (Dingel & Neiman) teleworkability score where Israeli institutional
# reality diverges sharply from the US-task-based prediction -- the standing example is teaching
# (ISCO 23): D&N scores it 0.966 (near-ceiling teleworkable), but Israeli teachers essentially
# don't work from home (realized 2022-23 usage 0.063) because schools stayed in-person by Ministry
# of Education policy, not by individual choice.
#
# A gap this size is real, not noise, for ISCO 23 (n = 12,881). But a flat gap threshold applied
# to every occupation regardless of sample size lets a handful of observations swap the index --
# e.g. ISCO 63 (subsistence farmers), n = 4, would swap 0.000 -> 0.750 on that alone. So the swap
# is only made when the gap exceeds the substantive threshold (gap_threshold) by more than the
# realized estimate's own sampling uncertainty: a one-sided test that the TRUE gap exceeds
# gap_threshold, at conf_level confidence, using a cluster-robust SE (cluster = IDPUF -- this
# project's own convention everywhere else regressions are run; roughly 15,000 IDPUFs repeat
# across the pooled 2022-2023 window this draws on by default, so an unclustered SE understates
# uncertainty by ~54% on average -- confirmed against the real data before this threshold was
# adopted). Occupations too thin to compute a cluster-robust SE at all (e.g. ISCO 63) fail the
# test automatically and keep their theoretical value, the same outcome a min_n floor would give,
# but without a second, independently-chosen number to justify.
calibrate_isco_exposure <- function(cleaned_df, exposure_isco2, wfh_col = "WFH",
                                    ref_year = c(2022, 2023), gap_threshold = 0.5,
                                    conf_level = 0.95) {

  df <- cleaned_df %>%
    filter(
      ShnatSeker %in% ref_year,
      Employed == 1,
      !is.na(MishlachYad_ISCO_08_2),
      !is.na(.data[[wfh_col]])
    ) %>%
    mutate(ISCO2 = MishlachYad_ISCO_08_2)

  z <- qnorm(1 - (1 - conf_level) / 2)

  # A cluster-robust SE is undefined for two known, expected reasons: fewer than 2 distinct
  # IDPUF (feols's vcov hits a singular matrix and fixest throws an ERROR from eigen(), not a
  # warning -- confirmed against the real data: ISCO 63's 4 rows all belong to one IDPUF, the same
  # person surveyed 4 times in 2023, and fixest reports "infinite or missing values in 'x'"), or a
  # constant outcome within the occupation (feols refuses an intercept-only fit on a constant DV).
  # Both are checked explicitly and handled the same way (kept at theoretical, not swapped) rather
  # than being funneled through a blanket tryCatch(error=..., warning=...) -- that would silently
  # swallow a genuinely unexpected failure too (e.g. a mistyped wfh_col), turning a real bug into
  # "nothing got swapped" with zero diagnostic trace. Any OTHER error is still caught (fixest is a
  # third-party dependency; a truly unanticipated failure shouldn't halt the whole pipeline) but is
  # always reported below with the specific occupation and error text, not swallowed silently.
  realized <- df %>%
    group_by(ISCO2) %>%
    group_modify(~ {
      n <- nrow(.x)
      p <- mean(.x[[wfh_col]])
      se_clustered <- NA_real_
      se_na_reason <- NA_character_
      if (n_distinct(.x$IDPUF) < 2) {
        se_na_reason <- "fewer than 2 distinct IDPUF"
      } else if (n_distinct(.x[[wfh_col]]) < 2) {
        se_na_reason <- "constant outcome within occupation"
      } else {
        se_clustered <- tryCatch({
          m <- feols(as.formula(paste(wfh_col, "~ 1")), data = .x, cluster = ~IDPUF, notes = FALSE)
          unname(se(m)["(Intercept)"])
        }, error = function(e) {
          se_na_reason <<- paste("unexpected fixest error:", conditionMessage(e))
          NA_real_
        })
      }
      tibble(n = n, realized_wfh = p, se_clustered = se_clustered, se_na_reason = se_na_reason)
    }) %>%
    ungroup()

  undefined <- filter(realized, is.na(se_clustered))
  if (nrow(undefined) > 0) {
    message(sprintf(
      "calibrate_isco_exposure: %d of %d occupations kept at their theoretical value (no cluster-robust SE could be computed):",
      nrow(undefined), nrow(realized)
    ))
    print(as.data.frame(select(undefined, ISCO2, n, se_na_reason)))
  }

  exposure_isco2 %>%
    left_join(realized, by = "ISCO2") %>%
    mutate(
      gap    = abs(realized_wfh - tele_ext),
      margin = gap - z * se_clustered - gap_threshold,
      swap   = !is.na(margin) & margin > 0,
      wfh_exposure_calibrated = if_else(swap, realized_wfh, tele_ext)
    ) %>%
    arrange(desc(gap))
}

# Build shift-share exposure by demographic cells based on pre-crisis years (2017-2019)
build_exposure_cells <- function(raw_all, exposure_isco2, 
                                 cell_vars = c("Min", "GilNK", "TeudaGvoha", "MachozMegurim")) {
  raw_all %>%
    filter(ShnatSeker %in% 2017:2019, Muasak == 1, !is.na(MishlachYad_ISCO_08_2)) %>%
    mutate(ISCO2 = suppressWarnings(as.numeric(MishlachYad_ISCO_08_2))) %>%
    filter(!is.na(ISCO2)) %>%
    count(across(all_of(cell_vars)), ISCO2, wt = MishkalSofi, name = "w") %>%
    left_join(exposure_isco2 %>% select(ISCO2, tele_ext), by = "ISCO2") %>%
    filter(!is.na(tele_ext)) %>%
    group_by(across(all_of(cell_vars))) %>%
    summarise(
      WFH_Exposure = weighted.mean(tele_ext, w),
      n_cell       = sum(w),
      .groups      = "drop"
    )
}