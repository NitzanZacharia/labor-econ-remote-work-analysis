# validation.R
# Data validation & quality guard layer (docs/ROADMAP.md Checkpoint 1). Enforces the hard-fail and
# soft-fail thresholds from docs/LLD.md's "Validation & Thresholds" section against the output of
# load_and_clean_data(), so every downstream analysis function builds on data that's been
# verified, not assumed, correct.
source("data_processing.R")

validate_cleaned_df <- function(cleaned_df, sex_filter = c("women", "men")) {

  sex_filter <- match.arg(sex_filter)
  min_code <- if (sex_filter == "women") 2 else 1

  # ── Hard-fail checks: stop() immediately, these should never happen ────────
  # (thresholds/rules per docs/LLD.md's "Hard-fail checks" table)

  if (!all(cleaned_df$Min == min_code)) {
    stop("validate_cleaned_df: found rows with Min != ", min_code, " -- the sex filter in ",
         "load_and_clean_data(sex_filter = '", sex_filter, "') is supposed to guarantee this.")
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

  regression_controls <- DEFAULT_CONTROLS
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

# Characterizes how much IDPUF (the individual identifier every regression in this repo clusters
# standard errors by) repeats across ShnatSeker years, and specifically across the Mother/Post
# design's Post==0/Post==1 divide. This is a reporting function, not a hard/soft-fail gate --
# CBS's rotating LFS panel design means some repetition is expected (confirmed directly in
# wfh_exposure_cells.R: a single IDPUF can carry 4 rows within one year alone). Clustering by
# IDPUF correctly absorbs within-person correlation in the *errors*, but that's a separate question
# from whether the same person is contributing rows to *both* sides of the Mother/Post design --
# if a meaningful share of IDPUFs do, the "pre" and "post" samples are not fully independent draws
# of distinct people, which matters for how Mother's/Post's identifying variation should be
# interpreted and has never previously been measured in this codebase.
check_idpuf_panel_structure <- function(cleaned_df) {
  n_idpuf <- n_distinct(cleaned_df$IDPUF)

  years_per_idpuf <- cleaned_df %>%
    distinct(IDPUF, ShnatSeker) %>%
    count(IDPUF, name = "n_years")
  multi_year_n <- sum(years_per_idpuf$n_years > 1)

  periods_per_idpuf <- cleaned_df %>%
    distinct(IDPUF, Post) %>%
    count(IDPUF, name = "n_periods")
  cross_period_n <- sum(periods_per_idpuf$n_periods > 1)

  message(sprintf(
    paste0(
      "check_idpuf_panel_structure: %d distinct IDPUF in cleaned_df.\n",
      "  %d (%.2f%%) appear in more than one ShnatSeker year.\n",
      "  %d (%.2f%%) appear in BOTH Post==0 (2017-2019) and Post==1 (2021-2023) rows -- ",
      "the same individual contributing to both sides of the Mother/Post design."
    ),
    n_idpuf,
    multi_year_n, 100 * multi_year_n / n_idpuf,
    cross_period_n, 100 * cross_period_n / n_idpuf
  ))

  invisible(list(
    n_idpuf        = n_idpuf,
    multi_year_n   = multi_year_n,
    cross_period_n = cross_period_n,
    idpuf_years    = years_per_idpuf,
    idpuf_periods  = periods_per_idpuf
  ))
}

# Verifies a raw-data assumption stated only in a comment, never previously checked in code:
# data_processing.R's WFH_RefWeek block claims AvadMeHaBayit is "asked only of the employed who
# actually worked that week (AvadBeshavua == 1), so the ~10,955 employed-but-absent per year are
# legitimately NA rather than 0." AvadBeshavua itself is never referenced anywhere else in this
# codebase (confirmed via grep) -- this is the first place it's actually used, specifically to
# check that claim rather than trust it.
#
# Restricted to Post==1 (2021+) employed rows where AvadMeHaBayit is genuinely BLANK (as opposed
# to an explicit code-9 "unknown" answer, which also produces WFH_RefWeek == NA but for an
# unrelated reason -- response uncertainty, not absence that week -- and isn't what the comment
# claims to explain). Pre-2021 rows are excluded because WFH_RefWeek is NA for them unconditionally
# (data_processing.R's ShnatSeker < 2021 branch fires first, regardless of AvadBeshavua), so
# checking them would say nothing about the claim.
#
# Tolerant, not a hard gate: AvadBeshavua is documented as a raw passthrough column in
# docs/LLD.md, but this still degrades gracefully (a message, not an error) if it's ever absent --
# e.g. for a 2017-only extract, where the whole WFH module may not exist at all.
check_wfh_refweek_avadbeshavua <- function(cleaned_df) {
  if (!"AvadBeshavua" %in% names(cleaned_df)) {
    message("check_wfh_refweek_avadbeshavua: 'AvadBeshavua' is not present in cleaned_df -- the ",
            "WFH_RefWeek-is-NA-because-not-asked-that-week claim in data_processing.R's comment ",
            "cannot be verified against this data.")
    return(invisible(list(available = FALSE)))
  }

  df <- cleaned_df %>% filter(Post == 1, Employed == 1, is.na(AvadMeHaBayit))
  n <- nrow(df)

  if (n == 0) {
    message("check_wfh_refweek_avadbeshavua: no employed, Post==1 rows with a blank ",
            "AvadMeHaBayit were found -- nothing to check.")
    return(invisible(list(available = TRUE, n = 0)))
  }

  consistent    <- sum(df$AvadBeshavua != 1, na.rm = TRUE)  # supports the comment's claim
  inconsistent  <- sum(df$AvadBeshavua == 1, na.rm = TRUE)  # contradicts it
  indeterminate <- sum(is.na(df$AvadBeshavua))              # AvadBeshavua itself missing

  message(sprintf(
    paste0(
      "check_wfh_refweek_avadbeshavua: of %d employed Post==1 row(s) with a blank AvadMeHaBayit, ",
      "%d (%.1f%%) have AvadBeshavua != 1 (consistent with the 'not asked because absent that ",
      "week' claim), %d (%.1f%%) have AvadBeshavua == 1 (INCONSISTENT -- worked that week but ",
      "AvadMeHaBayit is still blank), %d (%.1f%%) have AvadBeshavua itself missing (indeterminate)."
    ),
    n, consistent, 100 * consistent / n, inconsistent, 100 * inconsistent / n,
    indeterminate, 100 * indeterminate / n
  ))

  if (inconsistent > 0) {
    warning(sprintf(
      paste0(
        "check_wfh_refweek_avadbeshavua: %d row(s) contradict data_processing.R's WFH_RefWeek ",
        "comment (AvadBeshavua == 1 but AvadMeHaBayit is blank) -- the comment's causal claim may ",
        "not fully hold; review before relying on it."
      ),
      inconsistent
    ))
  }

  invisible(list(
    available     = TRUE,
    n             = n,
    consistent    = consistent,
    inconsistent  = inconsistent,
    indeterminate = indeterminate
  ))
}

# Guards the 5 remaining positional range-drops in data_processing.R's load_and_clean_data() (e.g.
# -(RamatDat:BituachLeumi)), which depend on the raw CSV's column *order*, not names. If a future
# CBS data release reorders or inserts a column, those ranges could silently start dropping (or
# keeping) the wrong columns -- no error, no warning, just wrong data downstream. This reads only
# the header row of every CSV in folder_path and, for each tracked boundary-column pair, asserts
# the exact ordered set of column names spanned between them is identical across every file --
# that span is exactly what select(-(a:b)) drops, so this is a direct guarantee that behavior
# hasn't drifted between years.
#
# Originally tracked 7 pairs. 2 (EizeChozemechushav:ChodeshKodemShaa, MimaHaMigbala:PniyaLmaasik)
# were converted to explicit any_of()-based name drops in data_processing.R (2017_Data.csv lacks
# all 4 of those boundary columns entirely, which made the positional check fail on a file that
# was never going to contain them) and are no longer positional, so there's nothing left here to
# check for them.
check_schema_drift <- function(folder_path) {
  if (!dir.exists(folder_path)) {
    stop("check_schema_drift: target data folder not found: ", folder_path)
  }

  files <- list.files(folder_path, pattern = "\\.csv$", full.names = TRUE)
  if (length(files) == 0) {
    stop("check_schema_drift: no CSV files found in ", folder_path)
  }

  range_pairs <- list(
    c("Yeladim0_1Prat", "Yeladim15_17Prat"),
    c("MisparHachlafa", "YachasKirvaNK"),
    c("MisparNefashotGilAvodaV2007", "MisparPrat"),
    c("ChipusAvodaSherutTaasuka", "ChipusAvodaOfenAcher"),
    c("RamatDat", "BituachLeumi")
  )

  read_header <- function(file) {
    first_line <- readLines(file, n = 1, warn = FALSE)
    strsplit(first_line, ",", fixed = TRUE)[[1]]
  }

  span_names <- function(header, a, b, file) {
    pos_a <- match(a, header)
    pos_b <- match(b, header)
    if (is.na(pos_a)) {
      stop("check_schema_drift: boundary column '", a, "' not found in ", basename(file), ".")
    }
    if (is.na(pos_b)) {
      stop("check_schema_drift: boundary column '", b, "' not found in ", basename(file), ".")
    }
    if (pos_a >= pos_b) {
      stop("check_schema_drift: boundary columns out of order in ", basename(file), " -- '", a,
           "' (position ", pos_a, ") is not before '", b, "' (position ", pos_b, ").")
    }
    header[pos_a:pos_b]
  }

  reference_file <- files[1]
  reference_header <- read_header(reference_file)
  reference_spans <- lapply(range_pairs, function(p) {
    span_names(reference_header, p[1], p[2], reference_file)
  })

  for (file in files[-1]) {
    header <- read_header(file)
    for (i in seq_along(range_pairs)) {
      pair <- range_pairs[[i]]
      this_span <- span_names(header, pair[1], pair[2], file)
      if (!identical(this_span, reference_spans[[i]])) {
        stop(
          "check_schema_drift: column order changed between '", basename(reference_file),
          "' and '", basename(file), "' for the range ", pair[1], ":", pair[2], ". Expected ",
          length(reference_spans[[i]]), " column(s) (",
          paste(reference_spans[[i]], collapse = ", "), "), but found ", length(this_span),
          " column(s) (", paste(this_span, collapse = ", "), "). The positional range-drop in ",
          "data_processing.R would silently drop the wrong columns for this file -- do not ",
          "proceed without investigating."
        )
      }
    }
  }

  invisible(TRUE)
}
