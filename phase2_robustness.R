# phase2_robustness.R
# Phase 2 specification-robustness checks, all layered on the RE-WEIGHTED primary DDD (the raking
# weights from age_balance_robustness.R), adopted as the working baseline after the Phase-1b
# age-imbalance finding. Does NOT modify main.R's primary DDD spec (main.R:149/:154).
#
#   2a. run_ddd_twoway_cluster()   -- two-way clustering: IDPUF + (occupation x year), alongside
#       the existing single-way IDPUF clustering.
#   2b. run_ddd_education_checks() -- (i) excludes ISCO==23 (teaching); (ii) adds an explicit
#       Mother:Post:EducationSector term alongside the existing WFH_Exposure interaction.
#   2c. run_ddd_weights_check()    -- confirms MishkalSofi (CBS design weight) is not currently
#       applied anywhere, then compares unweighted / rake-only / design-only / combined
#       (rake x design) versions of the primary spec to check the two weight types don't fight.
#
# All three share prepare_reweighted_ddd_df() so every check is built on the exact same base frame
# (WFH_Exposure joined, quartile-assigned, rake-weighted, EducationSector flagged) rather than each
# silently reconstructing its own slightly different version.
library(tidyverse)
library(fixest)
source(file.path("scripts", "data_processing.R"))
source("age_balance_robustness.R")

prepare_reweighted_ddd_df <- function(cleaned_df, exposure_cells, rake = NULL) {
  if (is.null(rake)) rake <- build_gilnk_rake_weights(cleaned_df, exposure_cells)

  ddd_df <- cleaned_df %>%
    left_join(exposure_cells, by = c("Min", "GilNK", "TeudaGvoha", "MachozMegurim")) %>%
    filter(!is.na(WFH_Exposure)) %>%
    assign_wfh_quartile(rake$breaks) %>%
    left_join(rake$weights, by = c("WFH_Exposure_Q", "Mother", "GilNK")) %>%
    mutate(EducationSector = as.integer(!is.na(MishlachYad_ISCO_08_2) & MishlachYad_ISCO_08_2 == 23))

  list(ddd_df = ddd_df, rake = rake)
}

# ── 2a: two-way clustering (IDPUF + occupation^year) ─────────────────────────────────────────
run_ddd_twoway_cluster <- function(cleaned_df, exposure_cells, rake = NULL, controls = DEFAULT_CONTROLS) {
  prep   <- prepare_reweighted_ddd_df(cleaned_df, exposure_cells, rake)
  ddd_df <- prep$ddd_df

  cell_fe_vars   <- c("GilNK", "TeudaGvoha", "MachozMegurim")
  other_controls <- setdiff(controls, cell_fe_vars)

  # Occupation x year clustering requires a defined occupation on every row, which non-employed
  # rows (and disclosure-masked codes) don't have. Dropping them here is a REAL sample-composition
  # change, not just a different SE calculation -- the cell-based exposure measure was chosen as
  # the primary spec specifically because it's defined for employed and non-employed alike (see
  # main.R's own comments), so this check necessarily departs from that on the occupation-cluster
  # side. Both the 1-way and 2-way numbers below are fit on the SAME (occupation-defined)
  # subsample, so the comparison between them isolates the clustering choice, not the sample cut;
  # the caller should separately compare against the full-sample reweighted baseline to see the
  # cost of the sample restriction itself.
  n_no_occ <- sum(is.na(ddd_df$MishlachYad_ISCO_08_2))
  message(sprintf(
    "run_ddd_twoway_cluster: %d of %d rows (%.1f%%) have no occupation code and are dropped for ",
    n_no_occ, nrow(ddd_df), 100 * n_no_occ / nrow(ddd_df)
  ))
  message("  this check only (occupation x year clustering needs a defined occupation on every row).")

  ddd_df_occ <- filter(ddd_df, !is.na(MishlachYad_ISCO_08_2))

  fit_both_clusters <- function(formula_rhs, fe = NULL) {
    f <- if (is.null(fe)) as.formula(paste("Employed ~", formula_rhs))
         else as.formula(paste("Employed ~", formula_rhs, "|", fe))
    list(
      one_way = feols(f, data = ddd_df_occ, weights = ~rake_weight, cluster = ~IDPUF),
      two_way = feols(f, data = ddd_df_occ, weights = ~rake_weight,
                       cluster = ~IDPUF + MishlachYad_ISCO_08_2^ShnatSeker)
    )
  }

  additive <- fit_both_clusters(paste("Mother * Post * WFH_Exposure +", paste(controls, collapse = " + ")))
  fe       <- fit_both_clusters(paste("Mother * Post * WFH_Exposure +", paste(other_controls, collapse = " + ")),
                                 fe = paste(cell_fe_vars, collapse = "^"))

  n_idpuf   <- n_distinct(ddd_df_occ$IDPUF)
  n_occyear <- n_distinct(paste(ddd_df_occ$MishlachYad_ISCO_08_2, ddd_df_occ$ShnatSeker))
  message(sprintf(
    "run_ddd_twoway_cluster: %d IDPUF clusters, %d occupation x year clusters (N=%d on the occupation-defined subsample).",
    n_idpuf, n_occyear, nrow(ddd_df_occ)
  ))

  print(etable(additive$one_way, additive$two_way, fe$one_way, fe$two_way,
               headers = c("Additive: 1-way (IDPUF)", "Additive: 2-way (+occ x year)",
                           "FE: 1-way (IDPUF)", "FE: 2-way (+occ x year)"),
               digits = 4))

  invisible(list(additive = additive, fe = fe, n_idpuf = n_idpuf, n_occyear = n_occyear,
                 n = nrow(ddd_df_occ)))
}

# ── 2b: education-sector transparency ─────────────────────────────────────────────────────────
run_ddd_education_checks <- function(cleaned_df, exposure_cells, rake = NULL, controls = DEFAULT_CONTROLS) {
  prep   <- prepare_reweighted_ddd_df(cleaned_df, exposure_cells, rake)
  ddd_df <- prep$ddd_df

  cell_fe_vars   <- c("GilNK", "TeudaGvoha", "MachozMegurim")
  other_controls <- setdiff(controls, cell_fe_vars)

  fit_pair <- function(data, extra_rhs = NULL) {
    extra <- if (!is.null(extra_rhs)) paste(" +", extra_rhs) else ""
    rhs_add <- paste0("Mother * Post * WFH_Exposure", extra, " + ", paste(controls, collapse = " + "))
    rhs_fe  <- paste0("Mother * Post * WFH_Exposure", extra, " + ", paste(other_controls, collapse = " + "),
                       " | ", paste(cell_fe_vars, collapse = "^"))
    list(
      additive = feols(as.formula(paste("Employed ~", rhs_add)), data = data, weights = ~rake_weight, cluster = ~IDPUF),
      fe       = feols(as.formula(paste("Employed ~", rhs_fe)),  data = data, weights = ~rake_weight, cluster = ~IDPUF)
    )
  }

  # (i) exclude ISCO == 23 -- keep non-employed / NA-occupation rows, drop only actual teachers.
  # (MishlachYad_ISCO_08_2 != 23 alone would ALSO drop every NA row, since NA != 23 evaluates to
  # NA and filter() drops NA results -- explicitly keeping is.na(...) avoids silently discarding
  # every non-employed person instead of just teachers.)
  n_excluded <- sum(!is.na(ddd_df$MishlachYad_ISCO_08_2) & ddd_df$MishlachYad_ISCO_08_2 == 23)
  message(sprintf("run_ddd_education_checks: excluding %d rows with MishlachYad_ISCO_08_2 == 23 (teaching).", n_excluded))
  ddd_df_excl <- filter(ddd_df, is.na(MishlachYad_ISCO_08_2) | MishlachYad_ISCO_08_2 != 23)
  res_excl <- fit_pair(ddd_df_excl)

  # (ii) explicit Mother:Post:EducationSector term, alongside the existing WFH_Exposure
  # interaction (not replacing it), full sample.
  res_dummy <- fit_pair(ddd_df, extra_rhs = "Mother:Post:EducationSector")

  print(etable(res_excl$additive, res_excl$fe,
               headers = c("Excl. ISCO23: additive", "Excl. ISCO23: cell FE"), digits = 4))
  print(etable(res_dummy$additive, res_dummy$fe,
               headers = c("+EducationSector: additive", "+EducationSector: cell FE"), digits = 4))

  invisible(list(exclude_isco23 = res_excl, education_dummy = res_dummy, n_excluded = n_excluded))
}

# ── 2c: survey (design) weight check ──────────────────────────────────────────────────────────
run_ddd_weights_check <- function(cleaned_df, exposure_cells, rake = NULL, controls = DEFAULT_CONTROLS) {
  prep   <- prepare_reweighted_ddd_df(cleaned_df, exposure_cells, rake)
  ddd_df <- prep$ddd_df %>% mutate(combined_weight = rake_weight * MishkalSofi)

  cell_fe_vars   <- c("GilNK", "TeudaGvoha", "MachozMegurim")
  other_controls <- setdiff(controls, cell_fe_vars)

  rhs_add <- paste("Mother * Post * WFH_Exposure +", paste(controls, collapse = " + "))
  rhs_fe  <- paste("Mother * Post * WFH_Exposure +", paste(other_controls, collapse = " + "),
                    "|", paste(cell_fe_vars, collapse = "^"))

  fit <- function(w) list(
    additive = feols(as.formula(paste("Employed ~", rhs_add)), data = ddd_df, weights = w, cluster = ~IDPUF),
    fe       = feols(as.formula(paste("Employed ~", rhs_fe)),  data = ddd_df, weights = w, cluster = ~IDPUF)
  )

  unweighted  <- fit(NULL)
  rake_only   <- fit(~rake_weight)
  design_only <- fit(~MishkalSofi)
  combined    <- fit(~combined_weight)

  message(sprintf(
    "run_ddd_weights_check: rake_weight range [%.3f, %.3f]; MishkalSofi range [%.2f, %.2f]; combined range [%.2f, %.2f].",
    min(ddd_df$rake_weight, na.rm = TRUE), max(ddd_df$rake_weight, na.rm = TRUE),
    min(ddd_df$MishkalSofi, na.rm = TRUE), max(ddd_df$MishkalSofi, na.rm = TRUE),
    min(ddd_df$combined_weight, na.rm = TRUE), max(ddd_df$combined_weight, na.rm = TRUE)
  ))

  print(etable(unweighted$additive, rake_only$additive, design_only$additive, combined$additive,
               headers = c("Unweighted", "Rake only", "MishkalSofi only", "Combined (rake x design)"),
               digits = 4))
  print(etable(unweighted$fe, rake_only$fe, design_only$fe, combined$fe,
               headers = c("Unweighted", "Rake only", "MishkalSofi only", "Combined (rake x design)"),
               digits = 4))

  invisible(list(unweighted = unweighted, rake_only = rake_only, design_only = design_only,
                 combined = combined))
}
