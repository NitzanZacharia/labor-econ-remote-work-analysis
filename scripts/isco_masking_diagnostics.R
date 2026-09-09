# isco_masking_diagnostics.R
# Sensitivity check for CBS's ISCO-08 disclosure-masking and the WFH-exposure index (audit
# finding: masking concentrates in thinly-populated occupation cells -- 7.5% of all employed 2021
# rows, 2.4% of the analysis sample -- and every place ISCO2 is used as a join key
# (wfh_exposure_index.R, wfh_exposure_cells.R) drops masked rows via !is.na(). If masked
# occupations differ systematically in realized WFH from unmasked ones, the exposure index is
# built on a non-random subsample of occupations, biasing it in an unknown direction).
#
# This can't be resolved outright -- a fully-masked "XX" row carries zero occupation signal at any
# resolution and is necessarily excluded here too. But a PARTIALLY masked row ("7X") still has its
# 1-digit major group recoverable as ISCO1 (data_processing.R). Comparing realized WFH between
# masked and unmasked rows *within the same ISCO1 major group* is therefore a defensible, if
# imperfect, proxy check:
#   - if masked and unmasked rows look similar within a major group, that's reassuring (though not
#     proof -- masking could still correlate with a finer distinction ISCO1 can't see);
#   - if they look different even after conditioning on the coarse occupation family, that's
#     evidence the masking-driven exclusion could be biasing the exposure index, and the gap
#     reported below quantifies by how much, group by group.
library(tidyverse)
library(fixest)
source(file.path("scripts", "data_processing.R"))

check_isco_masking_sensitivity <- function(cleaned_df, wfh_col = "WFH", ref_year = c(2022, 2023)) {

  df <- cleaned_df %>%
    filter(
      ShnatSeker %in% ref_year,
      Employed == 1,
      !is.na(ISCO1),               # excludes fully-masked ("XX") rows -- no signal survives at all
      !is.na(.data[[wfh_col]])
    ) %>%
    mutate(mask_label = if_else(ISCO_masked, "masked", "unmasked"))

  # ── Descriptive comparison: mean realized WFH, masked vs. unmasked, within each ISCO1 group ──
  by_group <- df %>%
    group_by(ISCO1, mask_label) %>%
    summarise(mean_wfh = mean(.data[[wfh_col]]), n = n(), .groups = "drop")

  comparison_wide <- by_group %>%
    pivot_wider(names_from = mask_label, values_from = c(mean_wfh, n)) %>%
    mutate(gap = mean_wfh_masked - mean_wfh_unmasked) %>%
    arrange(desc(abs(gap)))

  message("check_isco_masking_sensitivity: realized WFH, masked vs. unmasked, by ISCO1 major group:")
  print(as.data.frame(comparison_wide), digits = 3)

  # ── Formal test: does masking status predict WFH after absorbing ISCO1 major-group FE? ──
  # ISCO1 as a fixed effect (not an additive control) makes this an exactly within-group
  # comparison, matching comparison_wide above -- a group with only masked or only unmasked rows
  # is constant on ISCO_masked and contributes nothing (correctly absorbed by its own FE, not an
  # error).
  reg <- feols(as.formula(paste(wfh_col, "~ ISCO_masked | ISCO1")), data = df, cluster = ~IDPUF)
  print(etable(reg, headers = c("WFH ~ ISCO_masked | ISCO1 (within-group masking gap)"), digits = 4))

  invisible(list(
    by_group        = by_group,
    comparison_wide = comparison_wide,
    model           = reg
  ))
}
