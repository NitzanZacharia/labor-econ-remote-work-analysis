# basic_reg_by_child_age_event_study.R
# Year-by-year version of scripts/basic_reg_by_child_age.R's pooled ChildAgeGroup*Post check --
# tests (a) whether pre-2021 trends were flat for each child-age group (parallel-trends validity,
# a precondition the pooled Post spec never actually tested) and (b) whether any effect is
# concentrated in one post-period year (e.g. 2021, a COVID/daycare-disruption year) or persists
# through 2023 (relevant before ever trying to connect a result here to WFH, which grew steadily
# through 2023, not just in 2021).
#
# Mirrors Diagnostics.R's own pretrend idiom (Employed ~ Mother + i(ShnatSeker, ref=2019) +
# i(ShnatSeker, Mother, ref=2019) + controls), generalized from one Mother dummy to 5 child-age
# dummies -- i() needs a 0/1 (or numeric) second argument, so each ChildAgeGroup level gets its own
# dummy for the i(ShnatSeker, dummy, ref=2019) interaction; ChildAgeGroup itself (the factor) still
# supplies each group's own level effect, same role Mother's bare term plays in Diagnostics.R.
#
# Same child-age coding/non-mother-reference convention as basic_reg_by_child_age.R -- see that
# file's header for the GilYeledTzairMBNK data-integrity note.
library(tidyverse)
library(fixest)
source(file.path("scripts", "data_processing.R"))
source(file.path("scripts", "ddd_collinearity_diagnostics.R"))

run_child_age_event_study <- function(cleaned_df) {
  controls <- DEFAULT_CONTROLS
  child_age_levels <- c("Age0to1", "Age2to4", "Age5to9", "Age10to14", "Age15to17")

  df <- cleaned_df %>%
    filter(Mother == 0 | GilYeledTzairMBNK %in% 1:5) %>%
    mutate(
      ChildAgeGroup = case_when(
        Mother == 0            ~ "NonMother",
        GilYeledTzairMBNK == 1 ~ "Age0to1",
        GilYeledTzairMBNK == 2 ~ "Age2to4",
        GilYeledTzairMBNK == 3 ~ "Age5to9",
        GilYeledTzairMBNK == 4 ~ "Age10to14",
        GilYeledTzairMBNK == 5 ~ "Age15to17"
      ),
      ChildAgeGroup = factor(ChildAgeGroup, levels = c("NonMother", child_age_levels))
    )
  for (lvl in child_age_levels) {
    df[[paste0(lvl, "_d")]] <- as.integer(df$ChildAgeGroup == lvl)
  }

  i_terms <- paste0("i(ShnatSeker, ", child_age_levels, "_d, ref = 2019)", collapse = " + ")
  formula_event <- as.formula(paste(
    "Employed ~ ChildAgeGroup + i(ShnatSeker, ref = 2019) +", i_terms, "+",
    paste(controls, collapse = " + ")
  ))

  reg <- feols(formula_event, data = df, cluster = ~IDPUF)
  check_for_dropped_coefficients(reg, "run_child_age_event_study()'s Employed model")

  message("=== Event study: Employed ~ ChildAgeGroup x year (ref = 2019) + controls ===")
  table_event <- etable(reg, digits = 4)
  print(table_event)

  invisible(list(table = table_event, model = reg))
}
