# basic_reg_by_child_age.R
# Reduced-form Employed ~ Post interaction, granular by youngest-child age, to check whether the
# pooled null Mother:Post result (scripts/basic_regression.R's basic_reg()) is masking
# heterogeneity -- motivated by the raw employment_by_child_age_emp_by_period.csv pattern (larger
# post-2021 employment gains among mothers of school-age children than mothers of children under
# 5). Does NOT include WFH_Exposure -- Post bundles everything that changed 2021-2023, not just
# WFH, so this answers "did the post-2021 period affect employment differently by child age," not
# "did WFH." The WFH-linked version of this split already exists
# (robustness/mother_heterogeneity_robustness.R's run_ddd_by_child_age()) and is null in both
# subgroups; see docs/decisions/ for that context before treating any result here as WFH evidence.
#
# One pooled regression (Employed ~ ChildAgeGroup*Post + controls) against the WHOLE sample,
# rather than separate subsample regressions per age bin -- more efficient (shared controls/
# residual variance), and supports a single joint Wald test of whether the 5 child-age Post
# interactions differ from each other, rather than eyeballing which of several pairwise splits
# crosses p<0.05.
#
# GilYeledTzairMBNK is an unverified raw CBS passthrough (docs/LLD.md row 12); its "0 = no
# children" convention (asserted only in employment_by_child_age.R's header comment, never
# confirmed against real data for every Mother==0 row) is NOT relied on here -- the non-mother
# reference level is assigned from Mother directly, not from GilYeledTzairMBNK's raw value.
library(tidyverse)
library(fixest)
source(file.path("scripts", "data_processing.R"))
source(file.path("scripts", "ddd_collinearity_diagnostics.R"))

basic_reg_by_child_age <- function(cleaned_df, age_interacted = FALSE, outcome_var = "Employed") {
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
    )

  message(sprintf(
    "basic_reg_by_child_age: dropped %d row(s) with Mother==1 but GilYeledTzairMBNK outside 1:5.",
    nrow(cleaned_df) - nrow(df)
  ))
  n_by_group <- count(df, ChildAgeGroup)
  print(n_by_group)

  rhs <- paste("ChildAgeGroup * Post +", paste(controls, collapse = " + "))
  # Mirrors how Mother:GilNK was added to main.R's primary DDD (docs/decisions/
  # age-balance-robustness-chain.md): a purely additive GilNK control can't absorb an age
  # distribution that varies BY child-age group, since mothers of young kids are mechanically
  # younger than mothers of teens. GilNK's own main effect stays in `controls`; this just lets the
  # age-group employment profile vary by ChildAgeGroup on top of that.
  if (age_interacted) rhs <- paste(rhs, "+ ChildAgeGroup:GilNK")
  formula_employed <- as.formula(paste(outcome_var, "~", rhs))

  reg <- feols(formula_employed, data = df, cluster = ~IDPUF)
  check_for_dropped_coefficients(reg, "basic_reg_by_child_age()'s model")

  joint_test <- wald(reg, keep = "^ChildAgeGroup.*:Post$")

  message(sprintf(
    "=== Reduced-form %s ~ ChildAgeGroup*Post + controls%s ===",
    outcome_var, if (age_interacted) " + ChildAgeGroup:GilNK" else ""
  ))
  table_child_age <- etable(reg, headers = c(outcome_var), digits = 4)
  print(table_child_age)

  message(sprintf(
    "=== Joint Wald test, H0: the 5 ChildAgeGroup:Post coefficients are equal ===\nF(%d, %.0f) = %.4f, p = %.4f",
    joint_test$df1, joint_test$df2, joint_test$stat, joint_test$p
  ))

  invisible(list(
    table       = table_child_age,
    model       = reg,
    joint_test  = joint_test,
    n_by_group  = n_by_group
  ))
}
