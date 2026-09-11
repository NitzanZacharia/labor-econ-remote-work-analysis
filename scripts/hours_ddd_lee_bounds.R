# hours_ddd_lee_bounds.R
# Generalizes intensive_margin_lee_bounds.R's DiD-adapted Lee (2009) trimming bounds from the plain
# 2x2 (Mother x Post) intensive-margin regression to hours_ddd_regression.R's triple-interaction
# DDD (Mother x Post x WFH_Exposure). See docs/decisions/hours-ddd-pivot.md for the full rationale.
#
# ── Why this function uses TWO different WFH_Exposure measures ─────────────────────────────────
# hours_ddd_regression.R's point estimate uses the PURE occupation-level exposure
# (exposure_calibrated's wfh_exposure_calibrated, joined by MishlachYad_ISCO_08_2) as the
# continuous regressor -- it's the more precise measure of a specific job's teleworkability, but it
# is UNDEFINED for anyone without an observed occupation, i.e. the non-employed. The whole point of
# a Lee-bounds correction here is to bound the bias from those very rows being dropped -- which
# means the selection-into-employment counterfactual (s_ab below) must be computable for people who
# are NOT employed, so it cannot be stratified by an exposure measure that only exists for the
# employed. It is instead stratified by quartiles of the demographic-cell-based WFH_Exposure
# (build_exposure_cells()'s shift-share measure, defined for the full sample regardless of
# employment status -- the same measure the EXTENSIVE-margin primary DDD in main.R uses), reusing
# robustness/age_balance_robustness.R's existing compute_pre_period_quartile_breaks()/
# assign_wfh_quartile() helpers unchanged.
#
# So: cell-based WFH_Exposure quartiles stratify WHO gets bounded together (a property observable
# pre-employment); occupation-level WFH_Exposure is what the bounded regression actually estimates
# against (a property only observable once employed). Using one measure for both roles is not
# possible -- the occupation-level measure can't stratify the non-employed, and the cell-based
# measure is a coarser, noisier stand-in for what the DDD's own regressor is trying to capture (see
# docs/decisions/exposure-cell-granularity-fix.md's rejection of using a demographic-cell measure to
# approximate individual-level occupation exposure, and vice versa).
#
# ── The bound construction, generalized from intensive_margin_lee_bounds.R ─────────────────────
# For each quartile q of the cell-based WFH_Exposure (computed on the FULL cell-matched sample,
# employed and non-employed alike):
#   s_ab(q) = P(Employed==1 | Mother==a, Post==b, WFH_Exposure_Q==q)     for a,b in {0,1}
#   s11_counterfactual(q) = s10(q) + (s01(q) - s00(q))
# If s11(q) exceeds this counterfactual, trim_prop(q) = 1 - s11_counterfactual(q)/s11(q) is trimmed
# from that quartile's own Mother==1 & Post==1 slice of the EMPLOYED, occupation-matched sample
# (top-trim by WorkHoursCont for the lower bound, bottom-trim for the upper bound -- same
# monotone-selection assumption as the original function). Each quartile is trimmed independently,
# using its own selection rates -- this tests whether excess selection itself is concentrated in
# particular exposure quartiles, not just present on average. The four quartiles' trimmed subsets
# are recombined into one lower-bound sample and one upper-bound sample, and the full triple-
# interaction formula is refit on point/lower/upper exactly as hours_ddd_regression.R specifies it.
#
# ── Limitations (in addition to intensive_margin_lee_bounds.R's own, which all still apply here:
# only handles EXCESS selection, relies on the extensive-margin DiD's own parallel-trends
# assumption, assumes monotone selection, ties broken by row order) ────────────────────────────
# - The "point" (untrimmed) fit here additionally requires a matched CELL-based exposure (to be
#   assignable to a quartile), on top of hours_ddd_regression.R's own occupation-match requirement
#   -- so this function's own point estimate can differ very slightly in sample from calling
#   run_hours_ddd_regression() directly (the ~1.3% of rows with no matched exposure cell, per
#   docs/decisions/exposure-cell-granularity-fix.md, are additionally excluded here).
# - A quartile with very few Mother==1,Post==1 rows makes that quartile's own trim_prop noisy, and
#   if excess selection is detected in a quartile with a small denominator, the trim itself may
#   remove nearly all of that quartile's post-period mothers. n_by_quartile in the diagnostics
#   output should be checked before trusting the bounds; a warning is emitted for any quartile
#   below MIN_CELL_WARN rows.
library(tidyverse)
library(fixest)
source(file.path("scripts", "data_processing.R"))
source(file.path("scripts", "imbens_manski_ci.R"))
source(file.path("robustness", "age_balance_robustness.R"))

MIN_CELL_WARN <- 30

run_hours_ddd_lee_bounds <- function(cleaned_df, exposure_index, exposure_cells,
                                      controls = DEFAULT_CONTROLS) {

  exposure_join_vars <- setdiff(names(exposure_cells), c("WFH_Exposure", "n_cell"))
  breaks <- compute_pre_period_quartile_breaks(cleaned_df, exposure_cells)

  # Full sample (employed + non-employed) with a matched cell-based exposure, quartile-assigned --
  # this is what the selection-rate counterfactual is computed on.
  full_df <- cleaned_df %>%
    left_join(exposure_cells, by = exposure_join_vars) %>%
    filter(!is.na(WFH_Exposure)) %>%
    assign_wfh_quartile(breaks) %>%
    rename(WFH_Exposure_Cell = WFH_Exposure)

  quartiles <- sort(unique(full_df$WFH_Exposure_Q))

  get_rate <- function(m, p, q) {
    sub <- full_df$Employed[full_df$Mother == m & full_df$Post == p & full_df$WFH_Exposure_Q == q]
    if (length(sub) == 0) {
      stop("run_hours_ddd_lee_bounds: no rows found for Mother == ", m, ", Post == ", p,
           ", WFH_Exposure_Q == ", q, " -- all four (Mother, Post) cells must be present in ",
           "every quartile to compute the selection counterfactual.")
    }
    mean(sub == 1)
  }

  quartile_diag <- map_dfr(quartiles, function(q) {
    s00 <- get_rate(0, 0, q); s01 <- get_rate(0, 1, q); s10 <- get_rate(1, 0, q); s11 <- get_rate(1, 1, q)
    n11 <- sum(full_df$Mother == 1 & full_df$Post == 1 & full_df$WFH_Exposure_Q == q)
    s11_counterfactual <- s10 + (s01 - s00)
    excess    <- s11 > s11_counterfactual
    trim_prop <- if (excess) 1 - s11_counterfactual / s11 else 0
    tibble(WFH_Exposure_Q = q, s00 = s00, s01 = s01, s10 = s10, s11 = s11,
           s11_counterfactual = s11_counterfactual, n_mother1_post1 = n11,
           excess_selection = excess, trim_prop = trim_prop)
  })

  message("run_hours_ddd_lee_bounds: selection (employment) rates and trim proportions by WFH_Exposure quartile:")
  print(as.data.frame(quartile_diag), digits = 4)

  thin <- filter(quartile_diag, n_mother1_post1 < MIN_CELL_WARN)
  if (nrow(thin) > 0) {
    warning(sprintf(
      "run_hours_ddd_lee_bounds: %d quartile(s) have fewer than %d Mother=1,Post=1 rows (%s) -- their trim_prop/bounds may be noisy.",
      nrow(thin), MIN_CELL_WARN, paste(sprintf("Q%d: n=%d", thin$WFH_Exposure_Q, thin$n_mother1_post1), collapse = "; ")
    ))
  }

  # Employed, occupation-matched sample (mirrors hours_ddd_regression.R's join), carrying forward
  # each row's cell-based WFH_Exposure_Q from full_df.
  employed_df <- full_df %>%
    filter(Employed == 1) %>%
    inner_join(
      exposure_index %>% select(MishlachYad_ISCO_08_2 = occupation_code, WFH_Exposure = wfh_exposure),
      by = "MishlachYad_ISCO_08_2"
    )

  other_cells <- filter(employed_df, !(Mother == 1 & Post == 1))

  trim_by_quartile <- map(quartiles, function(q) {
    trim_prop_q <- quartile_diag$trim_prop[quartile_diag$WFH_Exposure_Q == q]
    cell_q <- filter(employed_df, Mother == 1, Post == 1, WFH_Exposure_Q == q)
    n_cell_q <- nrow(cell_q)

    if (n_cell_q == 0 || trim_prop_q <= 0) {
      return(list(lower = cell_q, upper = cell_q, n_trim = 0L, n_cell = n_cell_q))
    }

    n_trim <- floor(trim_prop_q * n_cell_q)
    ranked <- arrange(cell_q, WorkHoursCont)
    # seq_len(), not "1:(n_cell_q - n_trim)" -- the latter (as used in
    # intensive_margin_lee_bounds.R) produces a reversed 2-element sequence rather than zero rows
    # when n_trim == n_cell_q (100% trim); seq_len(0) correctly yields an empty selection.
    lower_kept <- slice(ranked, seq_len(max(n_cell_q - n_trim, 0)))
    upper_kept <- slice(ranked, if (n_trim < n_cell_q) (n_trim + 1):n_cell_q else integer(0))
    list(lower = lower_kept, upper = upper_kept, n_trim = n_trim, n_cell = n_cell_q)
  })

  n_trimmed_by_quartile <- tibble(
    WFH_Exposure_Q = quartiles,
    n_cell   = map_int(trim_by_quartile, "n_cell"),
    n_trimmed = map_int(trim_by_quartile, "n_trim")
  )

  lower_df <- bind_rows(other_cells, bind_rows(map(trim_by_quartile, "lower")))
  upper_df <- bind_rows(other_cells, bind_rows(map(trim_by_quartile, "upper")))

  rhs    <- paste("Mother*Post*WFH_Exposure", paste(controls, collapse = " + "), sep = " + ")
  formula_hours <- as.formula(paste("WorkHoursCont ~", rhs))
  # Same Moulton reasoning as hours_ddd_regression.R: WFH_Exposure here is the occupation-level
  # measure, assigned at ~40 ISCO-2 groups, not the individual.
  fit_on <- function(df) feols(formula_hours, data = df, cluster = ~MishlachYad_ISCO_08_2)

  point_reg <- fit_on(employed_df)
  lower_reg <- fit_on(lower_df)
  upper_reg <- fit_on(upper_df)

  co    <- function(m) unname(coef(m)[["Mother:Post:WFH_Exposure"]])
  se_of <- function(m) unname(se(m)[["Mother:Post:WFH_Exposure"]])

  se_lower <- se_of(lower_reg); se_point <- se_of(point_reg); se_upper <- se_of(upper_reg)
  z <- qnorm(0.975)
  bounds_table <- tibble(
    bound   = c("lower", "point (untrimmed)", "upper"),
    coef    = c(co(lower_reg), co(point_reg), co(upper_reg)),
    se      = c(se_lower, se_point, se_upper),
    ci_low  = c(co(lower_reg) - z * se_lower, co(point_reg) - z * se_point, co(upper_reg) - z * se_upper),
    ci_high = c(co(lower_reg) + z * se_lower, co(point_reg) + z * se_point, co(upper_reg) + z * se_upper)
  )
  print(as.data.frame(bounds_table), digits = 4)

  im_ci <- imbens_manski_ci(co(lower_reg), co(upper_reg), se_lower, se_upper)
  message(sprintf(
    "run_hours_ddd_lee_bounds: 95%% Imbens-Manski CI for Mother:Post:WFH_Exposure's identified set = [%.4f, %.4f] (c_alpha = %.3f).",
    im_ci$lower, im_ci$upper, im_ci$c_alpha
  ))

  invisible(list(
    table       = bounds_table,
    models      = list(point = point_reg, lower = lower_reg, upper = upper_reg),
    diagnostics = list(
      quartile_selection_rates = quartile_diag,
      n_trimmed_by_quartile    = n_trimmed_by_quartile,
      n_trimmed_total          = sum(n_trimmed_by_quartile$n_trimmed)
    ),
    imbens_manski_ci = im_ci
  ))
}
