# mother_heterogeneity_robustness.R
# Subgroup-heterogeneity comparison specs for the primary DDD, motivated by a gap: `Mother` is a
# single binary indicator ("any child <17"), pooling a mother of a 1-year-old with a mother of a
# 16-year-old, and a single mother with a partnered one, into one Mother:Post:WFH_Exposure
# coefficient. If WFH-driven labor-supply elasticity is concentrated in the highest-need subgroups
# (young child, no in-household backup), averaging against the larger low-elasticity majority is
# exactly the kind of masking a pooled binary Mother indicator would produce. Both split variables
# already exist in cleaned_df but were never wired into the DDD before: GilYeledTzairMBNK (youngest
# child's age bin, used only in the standalone descriptive scripts/employment_by_child_age.R) and
# MisparHorimYechidim (single-parent flag, cast to a factor in data_processing.R but not in
# DEFAULT_CONTROLS or used anywhere downstream).
#
# Does NOT modify main.R's primary DDD spec -- same "comparison spec, not a replacement" framing as
# age_balance_robustness.R. Both functions here refit main.R's EXACT Spec 1/Spec 2 formulas
# (Mother * Post * WFH_Exposure + Mother:GilNK + controls, cell-clustered) on a subsample, keeping
# the {Mother==0} comparison group identical across both halves of each split so the contrast is a
# clean subgroup restriction, not two differently-defined DDDs.
#
# Power caveat (report alongside every estimate, don't just eyeball the point estimate): each
# subgroup is smaller than the full mother population, so its MDE (compute_ddd_mde()) will be LARGER
# than the already-underpowered full-sample MDE (~20-26% of baseline, per docs/decisions/
# null-vs-power-audit.md and exposure-cell-granularity-fix.md) -- a subgroup null is not automatically
# a sharper zero than the full-sample one.
library(tidyverse)
library(fixest)
source(file.path("scripts", "data_processing.R"))

fit_ddd_subgroup <- function(sub_df, controls, cell_fe_vars) {
  other_controls  <- setdiff(controls, cell_fe_vars)
  cluster_formula <- as.formula(paste("~", paste(cell_fe_vars, collapse = "^")))

  additive <- feols(
    as.formula(paste("Employed ~ Mother * Post * WFH_Exposure + Mother:GilNK +",
                      paste(controls, collapse = " + "))),
    data = sub_df, cluster = cluster_formula
  )
  fe <- feols(
    as.formula(paste("Employed ~ Mother * Post * WFH_Exposure + Mother:GilNK +",
                      paste(other_controls, collapse = " + "),
                      "|", paste(cell_fe_vars, collapse = "^"))),
    data = sub_df, cluster = cluster_formula
  )
  check_for_dropped_coefficients(additive, "mother-heterogeneity subgroup Spec 1 (additive)")
  check_for_dropped_coefficients(fe, "mother-heterogeneity subgroup Spec 2 (cell FE)")

  list(
    additive = additive, fe = fe,
    mde_additive = compute_ddd_mde(additive, baseline_rate = mean(sub_df$Employed, na.rm = TRUE)),
    mde_fe       = compute_ddd_mde(fe, baseline_rate = mean(sub_df$Employed, na.rm = TRUE)),
    n = nrow(sub_df)
  )
}

join_exposure <- function(cleaned_df, exposure_cells) {
  exposure_join_vars <- setdiff(names(exposure_cells), c("WFH_Exposure", "n_cell"))
  cleaned_df %>% left_join(exposure_cells, by = exposure_join_vars) %>% filter(!is.na(WFH_Exposure))
}

# ── Split 1: youngest-child age ───────────────────────────────────────────────────────────────
# GilYeledTzairMBNK coding (scripts/employment_by_child_age.R's header comment): 0 = no children,
# 1 = age 0-1, 2 = age 2-4, 3 = age 5-9, 4 = age 10-14, 5 = age 15-17. "Young" = under 5 (codes 1-2),
# "older" = 5-17 (codes 3-5). Non-mothers (Mother==0, GilYeledTzairMBNK == 0 or NA) are the SAME
# comparison group in both halves.
run_ddd_by_child_age <- function(cleaned_df, exposure_cells, controls = DEFAULT_CONTROLS,
                                  cell_fe_vars = c("GilNK", "TeudaGvoha", "MachozMegurim")) {
  ddd_df <- join_exposure(cleaned_df, exposure_cells)

  non_mothers <- filter(ddd_df, Mother == 0)
  young_kids  <- filter(ddd_df, Mother == 1, GilYeledTzairMBNK %in% 1:2)
  older_kids  <- filter(ddd_df, Mother == 1, GilYeledTzairMBNK %in% 3:5)

  message(sprintf(
    "run_ddd_by_child_age: %d non-mothers | %d mothers of a child under 5 | %d mothers of a child 5-17.",
    nrow(non_mothers), nrow(young_kids), nrow(older_kids)
  ))

  young_df <- bind_rows(non_mothers, young_kids)
  older_df <- bind_rows(non_mothers, older_kids)

  message("Fitting the primary DDD spec on {non-mothers, mothers of a child under 5}...")
  young_fit <- fit_ddd_subgroup(young_df, controls, cell_fe_vars)
  message("Fitting the primary DDD spec on {non-mothers, mothers of a child 5-17}...")
  older_fit <- fit_ddd_subgroup(older_df, controls, cell_fe_vars)

  child_age_table <- etable(
    young_fit$additive, young_fit$fe, older_fit$additive, older_fit$fe,
    headers = c("Child <5: additive", "Child <5: cell FE",
                "Child 5-17: additive", "Child 5-17: cell FE"),
    digits = 4
  )
  print(child_age_table)

  mde_table <- bind_rows(
    young_additive = as.data.frame(young_fit$mde_additive[c("point_estimate", "se", "mde", "within_mde")]),
    young_fe       = as.data.frame(young_fit$mde_fe[c("point_estimate", "se", "mde", "within_mde")]),
    older_additive = as.data.frame(older_fit$mde_additive[c("point_estimate", "se", "mde", "within_mde")]),
    older_fe       = as.data.frame(older_fit$mde_fe[c("point_estimate", "se", "mde", "within_mde")]),
    .id = "spec"
  )
  message("=== Child-age subgroup MDEs (report alongside every point estimate -- see file header) ===")
  print(mde_table)

  invisible(list(young = young_fit, older = older_fit, table = child_age_table, mde_table = mde_table))
}

# ── Split 2: single-parent status ─────────────────────────────────────────────────────────────
# MisparHorimYechidim's exact coding is NOT documented anywhere in this repo (docs/LLD.md flags
# ~65 raw-passthrough columns, this one included, as CBS-codebook-only -- H20231031Codebook.xlsx is
# not checked in). ASSUMPTION, stated explicitly rather than silently baked in: MisparHorimYechidim
# is a count ("number of lone parents"), following the exact same convention data_processing.R
# already uses to build Mother itself (Mother <- as.integer(MisparYeladimAd17MB > 0)) -- so
# MisparHorimYechidim > 0 is read as "single parent" here. This has NOT been verified against the
# CBS codebook. The raw distribution by Mother status is printed below specifically so this
# assumption is checkable against a plausible single-parent rate before trusting the split.
run_ddd_by_single_parent <- function(cleaned_df, exposure_cells, controls = DEFAULT_CONTROLS,
                                      cell_fe_vars = c("GilNK", "TeudaGvoha", "MachozMegurim")) {
  ddd_df <- join_exposure(cleaned_df, exposure_cells) %>%
    mutate(single_parent_num = suppressWarnings(as.numeric(as.character(MisparHorimYechidim))))

  message("run_ddd_by_single_parent: MisparHorimYechidim distribution by Mother status (coding UNVERIFIED -- see file header)...")
  print(ddd_df %>% count(Mother, MisparHorimYechidim, single_parent_num))

  non_mothers    <- filter(ddd_df, Mother == 0)
  single_mothers <- filter(ddd_df, Mother == 1, single_parent_num > 0)
  partnered_mothers <- filter(ddd_df, Mother == 1, single_parent_num == 0)

  message(sprintf(
    "run_ddd_by_single_parent: %d non-mothers | %d single mothers | %d partnered mothers.",
    nrow(non_mothers), nrow(single_mothers), nrow(partnered_mothers)
  ))

  single_df    <- bind_rows(non_mothers, single_mothers)
  partnered_df <- bind_rows(non_mothers, partnered_mothers)

  message("Fitting the primary DDD spec on {non-mothers, single mothers}...")
  single_fit <- fit_ddd_subgroup(single_df, controls, cell_fe_vars)
  message("Fitting the primary DDD spec on {non-mothers, partnered mothers}...")
  partnered_fit <- fit_ddd_subgroup(partnered_df, controls, cell_fe_vars)

  single_parent_table <- etable(
    single_fit$additive, single_fit$fe, partnered_fit$additive, partnered_fit$fe,
    headers = c("Single mothers: additive", "Single mothers: cell FE",
                "Partnered mothers: additive", "Partnered mothers: cell FE"),
    digits = 4
  )
  print(single_parent_table)

  mde_table <- bind_rows(
    single_additive    = as.data.frame(single_fit$mde_additive[c("point_estimate", "se", "mde", "within_mde")]),
    single_fe          = as.data.frame(single_fit$mde_fe[c("point_estimate", "se", "mde", "within_mde")]),
    partnered_additive = as.data.frame(partnered_fit$mde_additive[c("point_estimate", "se", "mde", "within_mde")]),
    partnered_fe       = as.data.frame(partnered_fit$mde_fe[c("point_estimate", "se", "mde", "within_mde")]),
    .id = "spec"
  )
  message("=== Single-parent subgroup MDEs (report alongside every point estimate -- see file header) ===")
  print(mde_table)

  invisible(list(single = single_fit, partnered = partnered_fit, table = single_parent_table,
                 mde_table = mde_table))
}
