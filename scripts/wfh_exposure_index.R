# wfh_exposure_index.R
# Checkpoint 6 (docs/ROADMAP.md): occupation-level WFH-exposure measure for the planned
# Triple-Differences mechanism test (research doc Part 2 §2 / Part 4 §4). Anchor year is 2021, not
# the literally-specified 2020, per the decision recorded in
# docs/decisions/checkpoint6-wfh-anchor-year.md (2020 is excluded from this project's sample
# entirely -- no raw 2020 extract exists).
#
# Two caveats this function cannot fix on its own, both of which matter for how its output is
# used downstream (see wfh_exposure_cells.R for the construction that does address them):
#
#  1. The index is *realized* WFH in the anchor year, so it is measured after treatment. The
#     external teleworkability benchmark in israeli_cbs_wfh_2digit.csv is the exogenous
#     alternative; the two correlate 0.833 at ISCO-2 level on the 2021 file, which is why the
#     realized index is a defensible robustness check but not the right baseline.
#  2. Whatever frame is passed in defines the population the index is built from. Passing the
#     analysis sample (women 25-59) builds the third difference out of the same people who enter
#     the regression -- prefer a frame that excludes them, or at minimum covers all workers.

library(tidyverse)
source(file.path("scripts", "data_processing.R"))

build_wfh_exposure_index <- function(cleaned_df, isco_col = "MishlachYad_ISCO_08_2",
                                     wfh_col = "WFH", ref_year = 2021,
                                     weight_col = NULL, min_n = 0) {

  # Restrict to: the anchor year, employed individuals (an occupation code is only meaningful for
  # someone who has a job), and rows with both a known occupation and a known WFH status. Rows
  # failing any of these are excluded from the group entirely rather than propagating as NA.
  df_year <- cleaned_df %>%
    filter(
      ShnatSeker %in% ref_year,
      Employed == 1,
      !is.na(.data[[isco_col]]),
      !is.na(.data[[wfh_col]])
    )

  # Report how much of the anchor year the occupation code costs us. CBS disclosure-masks
  # MishlachYad_ISCO_08_2 ("XX", "7X", ...), and those rows are dropped by the !is.na() filter
  # above exactly like genuinely-missing ones -- 2.4% of employed women 25-59 in 2021 (7.5% of
  # all employed, since masking concentrates in thin occupation cells). Losing part of the frame
  # to a disclosure rule rather than to real missingness is worth stating in the paper.
  if ("ISCO_masked" %in% names(cleaned_df)) {
    anchor <- filter(cleaned_df, ShnatSeker %in% ref_year, Employed == 1)
    n_masked <- sum(anchor$ISCO_masked, na.rm = TRUE)
    if (n_masked > 0) {
      years_str <- paste(ref_year, collapse = "-")
      message(sprintf(
        "build_wfh_exposure_index: %d of %d employed %s rows (%.1f%%) have a disclosure-masked ISCO code.",
        n_masked, nrow(anchor), years_str, 100 * n_masked / nrow(anchor)
      ))
    }
  }

  idx <- df_year %>%
    group_by(occupation_code = .data[[isco_col]]) %>%
    summarise(
      wfh_exposure = if (is.null(weight_col)) {
        mean(.data[[wfh_col]])
      } else {
        weighted.mean(.data[[wfh_col]], .data[[weight_col]], na.rm = TRUE)
      },
      n            = n(),
      .groups      = "drop"
    ) %>%
    arrange(desc(wfh_exposure))

  # Occupations with a handful of observations contribute a near-random exposure value, and are
  # also the ones that carry real disclosure risk if the index is ever exported (see CLAUDE.md on
  # outputs/). min_n = 0 keeps the function a pure aggregator by default; pass min_n = 200 for a
  # publication-grade index built on the real microdata.
  if (min_n > 0) {
    n_thin <- sum(idx$n < min_n)
    if (n_thin > 0) {
      message(sprintf("build_wfh_exposure_index: dropping %d occupation(s) with n < %d.",
                      n_thin, min_n))
    }
    idx <- filter(idx, n >= min_n)
  }

  idx
}