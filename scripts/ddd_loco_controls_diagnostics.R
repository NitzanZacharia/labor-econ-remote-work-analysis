# ddd_loco_controls_diagnostics.R
# Leave-one-control-out (LOCO) coefficient-stability check for the primary DDD's Spec 1 (additive
# controls). Motivated by the age-balance chain's finding that GilNK -- one of DEFAULT_CONTROLS --
# was imbalanced between Mother==1/0 in a way that, once interacted (Mother:GilNK), materially
# changed the fitted model (see docs/decisions/age-balance-robustness-chain.md). This asks the same
# "is a control absorbing part of the mechanism instead of just controlling for it" question for
# every OTHER DEFAULT_CONTROLS member, without ever adding a new control -- only removing existing,
# already-justified ones one at a time and measuring how far Mother:Post:WFH_Exposure moves. That
# keeps this within CLAUDE.md's "don't add controls speculatively" boundary: nothing here proposes a
# new specification, it only audits the sensitivity of the one already in main.R.
#
# Motivated concretely by robustness/balance_test.R's real-data run: MatzavMishpachti's pre-period
# imbalance between mothers/non-mothers (total variation distance ~24/18/44/56 percentage points
# across WFH_Exposure quartiles, peaking in Q4) is larger and more quartile-varying than GilNK's own
# pattern ever was before Mother:GilNK was added -- this is the direct motivation for checking it
# here, not a blind sweep over every control.
#
# GilNK is treated specially: dropping it removes BOTH its additive term and the Mother:GilNK
# interaction (main.R's own addition), since a partial removal (dropping the additive term but
# keeping the interaction) wouldn't answer "what if age weren't controlled for at all" -- it would
# just reparameterize the same information. Dropping GilNK is included primarily as a sanity check:
# per the age-balance chain's own real-data history, this should show the largest coefficient shift
# of any control (main.R's Mother:Post:WFH_Exposure moved from ~0.103/0.131 before Mother:GilNK was
# added to -0.026/-0.019 after) -- if it doesn't, this diagnostic's own wiring is suspect and the
# read on the other controls shouldn't be trusted.
library(tidyverse)
library(fixest)

run_ddd_leave_one_control_out <- function(ddd_df, controls = DEFAULT_CONTROLS,
                                           cell_fe_vars = c("GilNK", "TeudaGvoha", "MachozMegurim")) {
  cell_cluster_formula <- as.formula(paste("~", paste(cell_fe_vars, collapse = "^")))

  fit_spec1 <- function(controls_in, include_mother_gilnk) {
    rhs <- paste(
      "Mother * Post * WFH_Exposure",
      if (include_mother_gilnk) "+ Mother:GilNK" else "",
      "+", paste(controls_in, collapse = " + ")
    )
    feols(as.formula(paste("Employed ~", rhs)), data = ddd_df, cluster = cell_cluster_formula)
  }

  message("run_ddd_leave_one_control_out: fitting the full-controls baseline (Spec 1)...")
  baseline <- fit_spec1(controls, include_mother_gilnk = TRUE)
  check_for_dropped_coefficients(baseline, "LOCO baseline (full controls)")

  target <- "Mother:Post:WFH_Exposure"
  baseline_est <- unname(coef(baseline)[target])
  baseline_se  <- unname(fixest::se(baseline)[target])

  shifts <- map_dfr(controls, function(dropped) {
    controls_in <- setdiff(controls, dropped)
    # Dropping GilNK removes the Mother:GilNK interaction too -- see header comment.
    include_mgk <- dropped != "GilNK"

    fit <- tryCatch(
      list(model = fit_spec1(controls_in, include_mgk), error = NULL),
      error = function(e) list(model = NULL, error = conditionMessage(e))
    )

    if (is.null(fit$model)) {
      message(sprintf(
        "run_ddd_leave_one_control_out: dropping '%s' failed to fit (%s) -- skipping.",
        dropped, fit$error
      ))
      return(tibble(
        dropped_control = dropped, estimate = NA_real_, se = NA_real_,
        shift_from_baseline = NA_real_, shift_in_baseline_se_units = NA_real_
      ))
    }

    check_for_dropped_coefficients(fit$model, paste0("LOCO (dropped ", dropped, ")"))
    est <- unname(coef(fit$model)[target])
    se_ <- unname(fixest::se(fit$model)[target])

    tibble(
      dropped_control             = dropped,
      estimate                    = est,
      se                          = se_,
      shift_from_baseline         = est - baseline_est,
      shift_in_baseline_se_units  = (est - baseline_est) / baseline_se
    )
  })

  result <- bind_rows(
    tibble(dropped_control = "(none -- full baseline)", estimate = baseline_est, se = baseline_se,
           shift_from_baseline = 0, shift_in_baseline_se_units = 0),
    shifts
  )

  message("=== LOCO: Mother:Post:WFH_Exposure, controls dropped one at a time ===")
  print(result, n = Inf)

  invisible(list(table = result, baseline_model = baseline))
}
