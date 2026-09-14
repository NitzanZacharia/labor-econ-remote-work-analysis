# basic_reg_by_single_parent.R
# Outside-the-box direction #2 (docs/decisions/extensive-margin-outside-the-box-directions.md):
# `robustness/mother_heterogeneity_robustness.R`'s run_ddd_by_single_parent() already splits
# mothers by single/partnered status, but only inside the full, underpowered
# Mother*Post*WFH_Exposure triple interaction on a subsample. Nobody has run the plain reduced-form
# `Post` interaction (no WFH_Exposure) the way basic_reg_by_child_age.R did for child age -- single
# mothers lack a second earner/caregiver to absorb childcare disruption, so this is a real
# candidate for a signal the pooled Mother indicator dilutes.
#
# MisparHorimYechidim's coding is UNVERIFIED beyond docs/LLD.md's raw-passthrough note -- same
# assumption as the existing split (count of lone parents; >0 read as "single parent"), carried
# over unchanged. The distribution by Mother status is printed before fitting anything, same
# discipline the existing split already applies.
library(tidyverse)
library(fixest)
source(file.path("scripts", "data_processing.R"))
source(file.path("scripts", "ddd_collinearity_diagnostics.R"))

basic_reg_by_single_parent <- function(cleaned_df) {
  controls <- DEFAULT_CONTROLS

  df <- cleaned_df %>%
    mutate(single_parent_num = suppressWarnings(as.numeric(as.character(MisparHorimYechidim))))

  message("basic_reg_by_single_parent: MisparHorimYechidim distribution by Mother status (coding UNVERIFIED -- see file header)...")
  print(df %>% count(Mother, MisparHorimYechidim, single_parent_num))

  df <- df %>%
    filter(Mother == 0 | !is.na(single_parent_num)) %>%
    mutate(
      SingleParentGroup = case_when(
        Mother == 0            ~ "NonMother",
        single_parent_num > 0  ~ "SingleMother",
        single_parent_num == 0 ~ "PartneredMother"
      ),
      SingleParentGroup = factor(SingleParentGroup,
        levels = c("NonMother", "SingleMother", "PartneredMother"))
    )

  n_by_group <- count(df, SingleParentGroup)
  print(n_by_group)

  rhs <- paste("SingleParentGroup * Post +", paste(controls, collapse = " + "))
  formula_employed <- as.formula(paste("Employed ~", rhs))

  reg <- feols(formula_employed, data = df, cluster = ~IDPUF)
  check_for_dropped_coefficients(reg, "basic_reg_by_single_parent()'s model")

  joint_test <- wald(reg, keep = "^SingleParentGroup.*:Post$")

  table_single_parent <- etable(reg, headers = c("Employed"), digits = 4)
  print(table_single_parent)
  message(sprintf(
    "=== Joint Wald test, H0: the SingleParentGroup:Post terms are jointly zero ===\nF(%d, %.0f) = %.4f, p = %.4f",
    joint_test$df1, joint_test$df2, joint_test$stat, joint_test$p
  ))

  invisible(list(table = table_single_parent, model = reg, joint_test = joint_test, n_by_group = n_by_group))
}
