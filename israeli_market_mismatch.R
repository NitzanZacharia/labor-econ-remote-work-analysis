library(tidyverse)
source("wfh_exposure_cells.R")

# Descriptive-only exhibit: how far did Israeli WFH adoption (2022-2023, the "new normal" after
# the initial pandemic disruption settled) diverge from Dingel & Neiman's theoretical
# teleworkability by occupation. This is a thin wrapper around calibrate_isco_exposure() -- the
# same function main.R uses to build the DDD's exposure measures -- so the swap/no-swap call here
# is identical to the one that actually feeds the regression, rather than an independently-chosen
# floor (this file previously used its own `filter(n > 50)`, main.R its own `min_n = 200`; the two
# disagreed on which occupations were "well-powered enough to trust").
check_market_mismatch <- function(cleaned_df, exposure_path = "israeli_cbs_wfh_2digit.csv", ...) {
  message("Calculating theoretical vs. actual WFH mismatch (2022-2023 average)...")

  dn_theoretical <- build_exposure_isco2(path = exposure_path)
  calibrate_isco_exposure(cleaned_df, dn_theoretical, ...) %>%
    mutate(israel_vs_us_gap = realized_wfh - tele_ext, abs_mismatch = gap) %>%
    arrange(desc(abs_mismatch))
}
