# age_balance_robustness.R
# Follow-up to the Phase 1b balance test: GilNK (age group) is imbalanced between Mother==1 and
# Mother==0 in the pre-period, concentrated in the lowest WFH_Exposure quartile, even though GilNK
# is already an additive DEFAULT_CONTROLS term. Builds three COMPARISON specs against the primary
# DDD's formulas (main.R:149 additive / :154 cell-FE) -- does NOT modify main.R.
#
#   1. diagnose_gilnk_by_quartile() -- age gap by Mother status, per WFH_Exposure quartile.
#   2. run_ddd_age_interacted()     -- adds Mother:GilNK (a fully saturated age x motherhood term)
#      to both of main.R's formulas, on top of the existing DEFAULT_CONTROLS.
#   3. build_gilnk_rake_weights() + run_ddd_reweighted() -- pre-period-derived weights that
#      equalize each Mother group's GilNK distribution (within WFH_Exposure quartile) to the
#      pooled pre-period quartile distribution, then applied to the full-period regression. For a
#      single discrete covariate with adequate cell sizes this is the exact solution entropy
#      balancing would also converge to (both minimize KL divergence to the same target marginal;
#      the two diverge only when exact reweighting is infeasible, e.g. a target cell with zero
#      support in one group -- build_gilnk_rake_weights() checks for and reports that). Kept
#      dependency-free (no new package) per CLAUDE.md's "flag before adding a dependency".
#
# All three use the SAME WFH_Exposure quartile definition -- breakpoints computed once from the
# pre-period distribution via compute_pre_period_quartile_breaks(), then applied identically to
# pre- and full-period rows via cut(). Computing quartiles independently on two different row sets
# (e.g. two separate ntile() calls) would silently misalign the quartile labels between the
# weight-building step and the full-period regression, since ntile()'s cutpoints depend on
# whichever rows it happens to be ranking.
library(tidyverse)
library(fixest)
source(file.path("scripts", "data_processing.R"))

compute_pre_period_quartile_breaks <- function(cleaned_df, exposure_cells) {
  pre_wfh <- cleaned_df %>%
    filter(ShnatSeker < 2020) %>%
    left_join(exposure_cells, by = c("Min", "GilNK", "TeudaGvoha", "MachozMegurim")) %>%
    filter(!is.na(WFH_Exposure)) %>%
    pull(WFH_Exposure)

  breaks <- quantile(pre_wfh, probs = c(0, 0.25, 0.5, 0.75, 1), na.rm = TRUE)
  if (any(duplicated(breaks))) {
    stop("compute_pre_period_quartile_breaks: duplicate quartile breakpoints (a mass point sits ",
         "exactly on a boundary) -- cut() would silently produce fewer than 4 bins. Inspect the ",
         "pre-period WFH_Exposure distribution before proceeding.")
  }
  breaks
}

assign_wfh_quartile <- function(df, breaks) {
  df %>% mutate(WFH_Exposure_Q = as.integer(cut(WFH_Exposure, breaks = breaks, labels = 1:4,
                                                 include.lowest = TRUE)))
}

# ── 1. Diagnose: is the imbalance uniform, or specific to the lowest quartile? ──────────────────
diagnose_gilnk_by_quartile <- function(cleaned_df, exposure_cells) {
  gilnk_num <- function(x) as.numeric(as.character(x))
  breaks <- compute_pre_period_quartile_breaks(cleaned_df, exposure_cells)

  pre_df <- cleaned_df %>%
    filter(ShnatSeker < 2020) %>%
    left_join(exposure_cells, by = c("Min", "GilNK", "TeudaGvoha", "MachozMegurim")) %>%
    filter(!is.na(WFH_Exposure)) %>%
    assign_wfh_quartile(breaks)

  gap <- pre_df %>%
    group_by(WFH_Exposure_Q) %>%
    group_modify(~ {
      tt <- t.test(gilnk_num(GilNK) ~ Mother, data = .x)
      # t.test()'s own $statistic is (group0 - group1)/se; flip sign to match the Mother1-minus-0
      # direction used for the reported gap, per the convention established in balance_test.R.
      tibble(
        mean_GilNK_Mother0 = unname(tt$estimate[1]),
        mean_GilNK_Mother1 = unname(tt$estimate[2]),
        gap_Mother1_minus_0 = unname(tt$estimate[2] - tt$estimate[1]),
        t_stat = -unname(tt$statistic),
        p_value = tt$p.value,
        n = nrow(.x)
      )
    }) %>%
    ungroup()

  message("=== GilNK (age-group) gap by Mother status, per WFH_Exposure quartile (pre-period) ===")
  print(gap)

  invisible(list(gap_by_quartile = gap, breaks = breaks, pre_df = pre_df))
}

# ── 2. Interacted-control spec: add Mother:GilNK to main.R:149/:154's formulas ──────────────────
run_ddd_age_interacted <- function(cleaned_df, exposure_cells, controls = DEFAULT_CONTROLS) {
  cell_fe_vars   <- c("GilNK", "TeudaGvoha", "MachozMegurim")
  other_controls <- setdiff(controls, cell_fe_vars)
  # Cell-level, not ~IDPUF: WFH_Exposure is constant within a (GilNK, TeudaGvoha, MachozMegurim)
  # cell, so individual-level clustering misses the correlation a shared exposure value and shared
  # unobserved cell shocks induce (Moulton problem) -- matches main.R's primary-spec fix (see
  # docs/decisions/calibrated-exposure-and-cell-ddd.md and age-balance-robustness-chain.md).
  cluster_formula <- as.formula(paste("~", paste(cell_fe_vars, collapse = "^")))

  ddd_df <- cleaned_df %>%
    left_join(exposure_cells, by = c("Min", "GilNK", "TeudaGvoha", "MachozMegurim"))

  additive <- feols(
    as.formula(paste("Employed ~ Mother * Post * WFH_Exposure + Mother:GilNK +",
                      paste(controls, collapse = " + "))),
    data = ddd_df, cluster = cluster_formula
  )
  # GilNK's main effect is already absorbed into the cell FE here; Mother:GilNK is not (the FE
  # groups by GilNK^TeudaGvoha^MachozMegurim jointly, not by an individual's own Mother status
  # within that cell), so adding it still adds new, non-redundant information to this spec.
  fe <- feols(
    as.formula(paste("Employed ~ Mother * Post * WFH_Exposure + Mother:GilNK +",
                      paste(other_controls, collapse = " + "),
                      "|", paste(cell_fe_vars, collapse = "^"))),
    data = ddd_df, cluster = cluster_formula
  )

  print(etable(additive, fe,
               headers = c("Age-interacted Spec 1: additive", "Age-interacted Spec 2: cell FE"),
               digits = 4))

  invisible(list(additive = additive, fe = fe))
}

# ── 3. Reweighted spec: raking weights on GilNK, pre-period, applied to the full period ─────────
build_gilnk_rake_weights <- function(cleaned_df, exposure_cells) {
  breaks <- compute_pre_period_quartile_breaks(cleaned_df, exposure_cells)

  pre_df <- cleaned_df %>%
    filter(ShnatSeker < 2020) %>%
    left_join(exposure_cells, by = c("Min", "GilNK", "TeudaGvoha", "MachozMegurim")) %>%
    filter(!is.na(WFH_Exposure)) %>%
    assign_wfh_quartile(breaks)

  # Target: the pooled (both Mother groups) GilNK distribution within each quartile.
  target <- pre_df %>%
    count(WFH_Exposure_Q, GilNK, name = "n_target") %>%
    group_by(WFH_Exposure_Q) %>%
    mutate(p_target = n_target / sum(n_target)) %>%
    ungroup()

  own <- pre_df %>%
    count(WFH_Exposure_Q, Mother, GilNK, name = "n_own") %>%
    group_by(WFH_Exposure_Q, Mother) %>%
    mutate(p_own = n_own / sum(n_own)) %>%
    ungroup()

  weights_tbl <- own %>%
    left_join(target %>% select(WFH_Exposure_Q, GilNK, p_target), by = c("WFH_Exposure_Q", "GilNK")) %>%
    mutate(rake_weight = p_target / p_own)

  extreme <- filter(weights_tbl, rake_weight > 10 | rake_weight < 0.1)
  if (nrow(extreme) > 0) {
    message(sprintf(
      "build_gilnk_rake_weights: %d of %d (quartile x Mother x GilNK) cells have an extreme raking weight (<0.1 or >10):",
      nrow(extreme), nrow(weights_tbl)
    ))
    print(as.data.frame(select(extreme, WFH_Exposure_Q, Mother, GilNK, n_own, p_own, p_target, rake_weight)))
  }

  list(weights = weights_tbl %>% select(WFH_Exposure_Q, Mother, GilNK, rake_weight), breaks = breaks)
}

run_ddd_reweighted <- function(cleaned_df, exposure_cells, controls = DEFAULT_CONTROLS,
                                rake = NULL) {
  if (is.null(rake)) rake <- build_gilnk_rake_weights(cleaned_df, exposure_cells)

  cell_fe_vars   <- c("GilNK", "TeudaGvoha", "MachozMegurim")
  other_controls <- setdiff(controls, cell_fe_vars)
  cluster_formula <- as.formula(paste("~", paste(cell_fe_vars, collapse = "^")))

  # Weights are keyed on (WFH_Exposure quartile x Mother x GilNK), a triple that exists
  # identically pre- and post-period, so the same pre-period-derived weight applies to every row
  # sharing that triple across the full sample, per "apply those weights to the full-period
  # regression".
  ddd_df <- cleaned_df %>%
    left_join(exposure_cells, by = c("Min", "GilNK", "TeudaGvoha", "MachozMegurim")) %>%
    filter(!is.na(WFH_Exposure)) %>%
    assign_wfh_quartile(rake$breaks) %>%
    left_join(rake$weights, by = c("WFH_Exposure_Q", "Mother", "GilNK"))

  n_total   <- nrow(ddd_df)
  n_missing <- sum(is.na(ddd_df$rake_weight))
  if (n_missing > 0) {
    message(sprintf(
      paste0("run_ddd_reweighted: %d of %d rows (%.1f%%) have no pre-period-derived weight for ",
             "their (quartile, Mother, GilNK) cell -- dropped by feols's listwise deletion."),
      n_missing, n_total, 100 * n_missing / n_total
    ))
  }

  additive <- feols(
    as.formula(paste("Employed ~ Mother * Post * WFH_Exposure +", paste(controls, collapse = " + "))),
    data = ddd_df, weights = ~rake_weight, cluster = cluster_formula
  )
  fe <- feols(
    as.formula(paste("Employed ~ Mother * Post * WFH_Exposure +", paste(other_controls, collapse = " + "),
                      "|", paste(cell_fe_vars, collapse = "^"))),
    data = ddd_df, weights = ~rake_weight, cluster = cluster_formula
  )

  print(etable(additive, fe,
               headers = c("Reweighted Spec 1: additive", "Reweighted Spec 2: cell FE"),
               digits = 4))

  invisible(list(rake = rake, additive = additive, fe = fe))
}
