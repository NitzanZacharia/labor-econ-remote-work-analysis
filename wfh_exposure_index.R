#wfh_exposure_index
# Checkpoint 6 (docs/ROADMAP.md): occupation-level WFH-exposure measure for the planned
# Triple-Differences mechanism test (research doc Part 2 §2 / Part 4 §4). Anchor year is 2021, not
# the literally-specified 2020, per the decision recorded in
# docs/decisions/checkpoint6-wfh-anchor-year.md (2020 is excluded from this project's sample
# entirely -- no raw 2020 extract exists).
library(tidyverse)
source("data_processing.R")

build_wfh_exposure_index <- function(cleaned_df, isco_col = "MishlachYad_ISCO_08_2",
                                      wfh_col = "WFH", ref_year = 2021) {

  # Restrict to: the anchor year, employed individuals (an occupation code is only meaningful for
  # someone who has a job), and rows with both a known occupation and a known WFH status. Rows
  # failing any of these are excluded from the group entirely rather than propagating as NA.
  df_year <- cleaned_df %>%
    filter(
      ShnatSeker == ref_year,
      Employed == 1,
      !is.na(.data[[isco_col]]),
      !is.na(.data[[wfh_col]])
    )

  df_year %>%
    group_by(occupation_code = .data[[isco_col]]) %>%
    summarise(
      wfh_exposure = mean(.data[[wfh_col]]),
      n            = n(),
      .groups      = "drop"
    ) %>%
    arrange(desc(wfh_exposure))
}
