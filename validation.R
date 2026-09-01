# validation.R
# Data validation & quality guard layer (docs/ROADMAP.md Checkpoint 1). Enforces the hard-fail and
# soft-fail thresholds from docs/LLD.md's "Validation & Thresholds" section against the output of
# load_and_clean_data(), so every downstream analysis function builds on data that's been
# verified, not assumed, correct.

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

# Guards the 7 positional range-drops in data_processing.R's load_and_clean_data() (e.g.
# -(RamatDat:BituachLeumi)), which depend on the raw CSV's column *order*, not names. If a future
# CBS data release reorders or inserts a column, those ranges could silently start dropping (or
# keeping) the wrong columns -- no error, no warning, just wrong data downstream. This reads only
# the header row of every CSV in folder_path and, for each of the 7 boundary-column pairs, asserts
# the exact ordered set of column names spanned between them is identical across every file --
# that span is exactly what select(-(a:b)) drops, so this is a direct guarantee that behavior
# hasn't drifted between years.
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
    c("EizeChozemechushav", "ChodeshKodemShaa"),
    c("MimaHaMigbala", "PniyaLmaasik"),
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
