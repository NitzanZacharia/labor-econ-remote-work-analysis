# intensive_margin_lee_bounds.R
# DiD-adapted Lee (2009) trimming bounds for the intensive-margin (WorkHoursCont) regression.
# See docs/decisions/intensive-margin-lee-bounds.md for the full decision memo (problem statement,
# alternatives considered, and this adaptation's stated limitations).
#
# run_intensive_margin_reg() (intensive_margin_regression.R) estimates WorkHoursCont ~ Mother*Post
# + controls on the Employed == 1 subsample. Employed is itself the outcome of this project's
# extensive-margin DiD (basic_regression.R) -- if WFH availability differentially pulls marginal
# mothers into employment post-2021 (exactly the mechanism this project is testing for), the
# post-period employed-mother sample is compositionally different from the pre-period one for
# reasons unrelated to hours, biasing the intensive-margin Mother:Post coefficient in an unknown
# direction. This is a textbook selection-on-a-mediator problem -- see Lee (2009), "Training,
# Wages, and Sample Selection: Estimating Sharp Bounds on Treatment Effects", Review of Economic
# Studies 76(3).
#
# ── The bound construction ───────────────────────────────────────────────────
# Classic Lee bounds compare one treated group to one control group with a fixed selection rate,
# trimming the treated group's outcome distribution down to match. This project's design has two
# dimensions (Mother, Post), so "treatment" here is specifically Post's *differential* effect on
# Mother==1's selection into employment, relative to what Mother==0's own pre/post change in
# selection implies (a parallel-trends-in-selection counterfactual):
#
#   s_ab = P(Employed==1 | Mother==a, Post==b)          for a,b in {0,1}
#   s11_counterfactual = s10 + (s01 - s00)               (implied Post effect for mothers, absent
#                                                          any differential WFH-driven entry)
#
# If the *actual* s11 exceeds this counterfactual, mothers' employment rose by more than the
# parallel-trends benchmark after 2021 -- there are "excess" employed mothers in the post period
# whose hours are not comparable to the pre-period sample. The excess share
# p = 1 - s11_counterfactual / s11 is trimmed from the Mother==1 & Post==1 cell's WorkHoursCont
# distribution -- from the top for the lower bound, from the bottom for the upper bound (Lee's
# standard monotone-selection assumption: the marginal entrants have either the highest or the
# lowest hours of anyone in the cell) -- and Mother:Post is re-estimated on each trimmed sample.
# Every other cell is left untouched.
#
# If s11 does NOT exceed the counterfactual, there is nothing to trim under this construction and
# the bounds collapse to the untrimmed point estimate (see "Limitations" below).
#
# Deliberately consistent with this project's documented decision (README.md's Known Limitations,
# CLAUDE.md) not to apply MishkalSofi survey weights anywhere: the selection rates s_ab below are
# unweighted, matching every other regression in this repo.
#
# ── Limitations of this adaptation, stated explicitly ───────────────────────
# - Only handles excess selection in the Mother==1,Post==1 cell -- the direction this project's own
#   hypothesis predicts (WFH narrowing the penalty by pulling marginal mothers into work). If the
#   data instead showed *under*-selection in that cell relative to the counterfactual, this
#   construction does not produce a bound: under-selection is a missing-data problem, not an
#   excess-observed-data problem, and Lee-style trimming doesn't address it.
# - Relies on the same parallel-trends assumption already underlying the extensive-margin DiD
#   itself (see Diagnostics.R's pretrend check) to define the selection counterfactual s11*.
# - Assumes monotone selection (WFH availability weakly increases, never decreases, a mother's
#   probability of employment) to justify trimming from a single tail rather than modeling the
#   selection mechanism directly.
# - Ties in WorkHoursCont (common -- it's a bin-median lookup, so many rows share exact values)
#   are broken by row order after arrange(), not randomized. With a large trimmed count this
#   averages out; with a small one it's a minor source of bound imprecision worth noting if the
#   trimmed n is small.
library(tidyverse)
library(fixest)
source("data_processing.R")

run_intensive_margin_lee_bounds <- function(cleaned_df, controls = DEFAULT_CONTROLS) {

  # ── Selection rates by (Mother, Post) cell, and the implied counterfactual ──
  sel_rates <- cleaned_df %>%
    group_by(Mother, Post) %>%
    summarise(selection_rate = mean(Employed == 1), n = n(), .groups = "drop")

  get_rate <- function(m, p) {
    rate <- sel_rates$selection_rate[sel_rates$Mother == m & sel_rates$Post == p]
    if (length(rate) == 0) {
      stop("run_intensive_margin_lee_bounds: no rows found for Mother == ", m, ", Post == ", p,
           " -- all four (Mother, Post) cells must be present to compute the selection ",
           "counterfactual.")
    }
    rate
  }
  s00 <- get_rate(0, 0); s01 <- get_rate(0, 1); s10 <- get_rate(1, 0); s11 <- get_rate(1, 1)
  s11_counterfactual <- s10 + (s01 - s00)

  excess    <- s11 > s11_counterfactual
  trim_prop <- if (excess) 1 - s11_counterfactual / s11 else 0

  message(sprintf(
    paste0(
      "run_intensive_margin_lee_bounds: selection (employment) rates -- ",
      "Mother=0,Post=0: %.4f | Mother=0,Post=1: %.4f | Mother=1,Post=0: %.4f | ",
      "Mother=1,Post=1: %.4f (parallel-trends counterfactual: %.4f).\n  %s"
    ),
    s00, s01, s10, s11, s11_counterfactual,
    if (excess) {
      sprintf("Excess selection detected in Mother=1,Post=1: trimming %.2f%% of that cell.",
              100 * trim_prop)
    } else {
      paste("No excess selection in Mother=1,Post=1 relative to the parallel-trends",
            "counterfactual -- bounds collapse to the untrimmed point estimate.")
    }
  ))

  rhs           <- paste("Mother + Post + Mother:Post", paste(controls, collapse = " + "), sep = " + ")
  formula_hours <- as.formula(paste("WorkHoursCont ~", rhs))
  fit_on        <- function(df) feols(formula_hours, data = df, cluster = ~IDPUF)

  employed_df <- filter(cleaned_df, Employed == 1)
  point_reg   <- fit_on(employed_df)

  if (!excess || trim_prop <= 0) {
    lower_reg <- point_reg
    upper_reg <- point_reg
    n_trimmed <- 0L
  } else {
    treated_cell <- filter(employed_df, Mother == 1, Post == 1)
    other_cells  <- filter(employed_df, !(Mother == 1 & Post == 1))
    n_cell        <- nrow(treated_cell)
    n_trim        <- floor(trim_prop * n_cell)

    ranked <- arrange(treated_cell, WorkHoursCont)
    # Lower bound: drop the highest-hours n_trim rows (marginal entrants assumed to work the most).
    trimmed_for_lower <- if (n_trim > 0) slice(ranked, 1:(n_cell - n_trim)) else ranked
    # Upper bound: drop the lowest-hours n_trim rows (marginal entrants assumed to work the least).
    trimmed_for_upper <- if (n_trim > 0) slice(ranked, (n_trim + 1):n_cell) else ranked

    lower_reg <- fit_on(bind_rows(other_cells, trimmed_for_lower))
    upper_reg <- fit_on(bind_rows(other_cells, trimmed_for_upper))
    n_trimmed <- n_trim
  }

  co <- function(m) unname(coef(m)[["Mother:Post"]])
  bounds_table <- tibble(
    bound            = c("lower", "point (untrimmed)", "upper"),
    mother_post_coef = c(co(lower_reg), co(point_reg), co(upper_reg))
  )
  print(as.data.frame(bounds_table), digits = 4)

  return(invisible(list(
    table       = bounds_table,
    models      = list(point = point_reg, lower = lower_reg, upper = upper_reg),
    diagnostics = list(
      selection_rates    = sel_rates,
      s11_counterfactual = s11_counterfactual,
      excess_selection   = excess,
      trim_prop          = trim_prop,
      n_trimmed          = n_trimmed
    )
  )))
}
