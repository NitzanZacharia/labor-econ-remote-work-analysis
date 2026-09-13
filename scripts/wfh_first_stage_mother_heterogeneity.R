# wfh_first_stage_mother_heterogeneity.R
# Extends wfh_first_stage_check.R's relevance check (does WFH_Exposure predict realized WFH-taking?)
# to ask whether that first-stage relationship is HOMOGENEOUS across Mother status -- the primary
# DDD's implicit assumption is that the same cell-level WFH_Exposure value represents the same
# treatment "dose" for mothers and non-mothers alike. If employers accommodate WFH requests
# differently for mothers, or mothers self-select into WFH harder conditional on occupation/cell,
# the same nominal WFH_Exposure could translate into a systematically different realized WFH_RefWeek
# for mothers -- which would dilute a real, mother-specific first-stage-to-outcome link into the
# pooled DDD's null triple interaction, without that dilution showing up anywhere in the primary
# DDD's own diagnostics (which never test the first stage BY Mother group).
#
# Same Post==1-only restriction as check_wfh_first_stage_relevance() and for the identical reason:
# WFH/WFH_RefWeek are 100% NA pre-2021 by CBS survey design, so no pre/post first stage is
# estimable at all (see wfh_first_stage_check.R's header and data_processing.R's WFH block comment).
# This uses the FULL Post==1 individual-level sample (not the cell-collapsed primary DDD frame), so
# it is not bottlenecked by the primary DDD's documented cell-level MDE problem (docs/decisions/
# null-vs-power-audit.md, exposure-cell-granularity-fix.md) -- it is the best-powered test available
# for whether the exposure measure's "dose" is homogeneous across Mother status.
#
# WFH_Share (continuous WFH-hours share, capped at 1) is checked alongside the binary WFH_RefWeek
# for the same reason main.R's own design already treats intensive vs. extensive realized-WFH
# margins as informative separately (see WorkHoursCont / WFH_Share in data_processing.R) -- a
# Mother:WFH_Exposure interaction that only shows up on one of the two outcomes is itself an
# informative distinction (e.g. mothers converting exposure into SOME remote work but not full-time
# remote work, or vice versa).
library(tidyverse)
library(fixest)

check_wfh_first_stage_by_mother <- function(ddd_df, controls = DEFAULT_CONTROLS,
                                             cell_fe_vars = c("GilNK", "TeudaGvoha", "MachozMegurim")) {
  other_controls <- setdiff(controls, cell_fe_vars)
  cell_cluster_formula <- as.formula(paste("~", paste(cell_fe_vars, collapse = "^")))

  post_df <- ddd_df %>% filter(Post == 1)

  message("check_wfh_first_stage_by_mother: testing Mother:WFH_Exposure on realized WFH (Post==1 only)...")

  fit <- function(outcome) {
    feols(
      as.formula(paste(
        outcome, "~ WFH_Exposure * Mother +", paste(other_controls, collapse = " + ")
      )),
      data = post_df, cluster = cell_cluster_formula
    )
  }

  refweek_reg <- fit("WFH_RefWeek")
  share_reg   <- fit("WFH_Share")

  check_for_dropped_coefficients(refweek_reg, "WFH first-stage by Mother (WFH_RefWeek)")
  check_for_dropped_coefficients(share_reg, "WFH first-stage by Mother (WFH_Share)")

  first_stage_mother_table <- etable(
    refweek_reg, share_reg,
    headers = c("Binary: WFH_RefWeek", "Continuous: WFH_Share"),
    digits = 4
  )
  print(first_stage_mother_table)

  invisible(list(
    refweek_reg = refweek_reg,
    share_reg   = share_reg,
    table       = first_stage_mother_table
  ))
}
