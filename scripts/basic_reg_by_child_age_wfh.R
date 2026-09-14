# basic_reg_by_child_age_wfh.R
# WFH-linkage attempt for the validated reduced-form child-age signal (scripts/
# basic_reg_by_child_age.R / basic_reg_by_child_age_event_study.R): mothers of children under 5
# show a real (survives an age-confound check, a furlough-contamination check, and has flat
# pre-trends), but not-yet-WFH-attributed, negative relative employment shift post-2021.
#
# This tests whether that shift is concentrated in occupations more exposed to WFH -- the same
# question main.R's primary DDD asks of Mother, generalized here to ChildAgeGroup, using the SAME
# primary exposure measure (main.R section 8a's cell-based shift-share WFH_Exposure) and the same
# Spec 1 formula shape (Mother*Post*WFH_Exposure + Mother:GilNK + DEFAULT_CONTROLS, cell-clustered)
# -- just with ChildAgeGroup's 6 levels standing in for Mother's single 0/1.
#
# Expectation going in, stated for the record before running: the coarse (child<5 vs 5-17) version
# of exactly this test already exists (robustness/mother_heterogeneity_robustness.R's
# run_ddd_by_child_age()) and is null for both subgroups -- and subgroup DDDs are documented there
# as MORE underpowered than the already-underpowered full-sample DDD (docs/decisions/
# null-vs-power-audit.md, exposure-cell-granularity-fix.md). This granular, pooled version is a
# more targeted test than that one, but is not expected to escape the same power ceiling.
library(tidyverse)
library(fixest)
source(file.path("scripts", "data_processing.R"))
source(file.path("scripts", "ddd_collinearity_diagnostics.R"))

run_child_age_wfh_ddd <- function(cleaned_df, exposure_cells, exposure_cell_vars,
                                   cell_fe_vars = c("GilNK", "TeudaGvoha", "MachozMegurim")) {
  controls <- DEFAULT_CONTROLS

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
      ChildAgeGroup = factor(
        ChildAgeGroup,
        levels = c("NonMother", "Age0to1", "Age2to4", "Age5to9", "Age10to14", "Age15to17")
      )
    ) %>%
    left_join(exposure_cells, by = exposure_cell_vars)

  message(sprintf(
    "run_child_age_wfh_ddd: %d of %d rows unmatched to an exposure cell (WFH_Exposure NA).",
    sum(is.na(df$WFH_Exposure)), nrow(df)
  ))
  df <- filter(df, !is.na(WFH_Exposure))

  cluster_formula <- as.formula(paste("~", paste(cell_fe_vars, collapse = "^")))
  formula_wfh <- as.formula(paste(
    "Employed ~ ChildAgeGroup * Post * WFH_Exposure + ChildAgeGroup:GilNK +",
    paste(controls, collapse = " + ")
  ))

  reg <- feols(formula_wfh, data = df, cluster = cluster_formula)
  check_for_dropped_coefficients(reg, "run_child_age_wfh_ddd()'s Employed model")

  joint_test <- wald(reg, keep = "^ChildAgeGroup.*:Post:WFH_Exposure$")

  message("=== Employed ~ ChildAgeGroup*Post*WFH_Exposure + ChildAgeGroup:GilNK + controls ===")
  table_wfh <- etable(reg, headers = c("Employed"), digits = 4)
  print(table_wfh)

  message(sprintf(
    "=== Joint Wald test, H0: the 5 ChildAgeGroup:Post:WFH_Exposure coefficients are equal ===\nF(%d, %.0f) = %.4f, p = %.4f",
    joint_test$df1, joint_test$df2, joint_test$stat, joint_test$p
  ))

  invisible(list(table = table_wfh, model = reg, joint_test = joint_test))
}
