# validation.R
# Data validation & quality guard layer (docs/ROADMAP.md Checkpoint 1). Enforces the hard-fail and
# soft-fail thresholds from docs/LLD.md's "Validation & Thresholds" section against the output of
# load_and_clean_data(), so every downstream analysis function builds on data that's been
# verified, not assumed, correct.

validate_cleaned_df <- function(cleaned_df) {

  # ── Hard-fail checks: stop() immediately, these should never happen ────────
  # (thresholds/rules per docs/LLD.md's "Hard-fail checks" table)

  if (!all(cleaned_df$Min == 2)) {
    stop("validate_cleaned_df: found rows with Min != 2 -- the sex filter in load_and_clean_data() ",
         "is supposed to guarantee women-only rows.")
  }

  if (!all(as.integer(as.character(cleaned_df$GilNK)) %in% 3:7)) {
    stop("validate_cleaned_df: found rows with GilNK outside 3:7 -- the age-group filter in ",
         "load_and_clean_data() is supposed to guarantee ages 25-59.")
  }

  valid_years <- c(2017, 2018, 2019, 2021, 2022, 2023)
  if (!all(cleaned_df$ShnatSeker %in% valid_years)) {
    stop("validate_cleaned_df: found rows with ShnatSeker outside the valid year set (",
         paste(valid_years, collapse = ", "), ") -- 2020 (or any other year) must never survive ",
         "the filter in load_and_clean_data().")
  }

  for (col in c("Employed", "Mother", "Post")) {
    n_na <- sum(is.na(cleaned_df[[col]]))
    if (n_na != 0) {
      stop("validate_cleaned_df: '", col, "' has ", n_na, " NA value(s). It is derived from ",
           "always-defined inputs and must never be NA -- this indicates a regression in ",
           "load_and_clean_data()'s derivation logic, not real-world missingness.")
    }
  }

  if (!(nrow(cleaned_df) > 0)) {
    stop("validate_cleaned_df: cleaned_df has zero rows.")
  }

  # ── Soft-fail checks: warn(), don't stop -- these can legitimately happen ──
  # (thresholds/rules per docs/LLD.md's "Soft-fail / warn thresholds" table)

  na_rate <- function(col) mean(is.na(cleaned_df[[col]])) * 100

  regression_controls <- c("MatzavMishpachti", "Dat", "GilNK", "MachozMegurim", "TeudaGvoha")
  for (col in regression_controls) {
    rate <- na_rate(col)
    if (rate > 5) {
      warning(sprintf(
        paste0("validate_cleaned_df: regression control '%s' has %.2f%% NA (> 5%% threshold) -- ",
               "this will meaningfully shrink the regression's effective sample via fixest's ",
               "listwise deletion."),
        col, rate
      ))
    }
  }

  # WorksOutsideLocality has its own, looser threshold: its NA is structurally expected
  # (DargatNayadut codes 0/8 = didn't work / unknown), not a data-quality problem on its own.
  wol_rate <- na_rate("WorksOutsideLocality")
  if (wol_rate > 20) {
    warning(sprintf(
      "validate_cleaned_df: WorksOutsideLocality has %.2f%% NA (> ~20%% threshold).", wol_rate
    ))
  }

  # Other comparative-stats-only variables (not regression controls, not WorksOutsideLocality):
  # WFH's ~64% NA is structurally expected (pre-2021 undefined by design), so this threshold sits
  # well above that to avoid a false positive while still catching a genuinely broken variable.
  comparative_stats_only <- c("WFH", "WorkHoursCont", "BirthContinent")
  for (col in comparative_stats_only) {
    rate <- na_rate(col)
    if (rate > 70) {
      warning(sprintf(
        "validate_cleaned_df: comparative-stats-only variable '%s' has %.2f%% NA (> 70%% threshold).",
        col, rate
      ))
    }
  }

  invisible(TRUE)
}
