# diagnostics.R
library(tidyverse)
library(fixest)

run_diagnostics <- function(cleaned_df) {
  
  # ── 1. 2x2 DiD table ─────────────────────────────────────────────────────
  # Employment rate by Mother/Post cells.
  # The DiD is meaningful if:
  #   [emp(Mother=1, Post=1) - emp(Mother=1, Post=0)] ≠
  #   [emp(Mother=0, Post=1) - emp(Mother=0, Post=0)]
  message("=== 2x2 DiD employment rates ===")
  did_table <- cleaned_df %>%
    group_by(Mother, Post) %>%
    summarise(emp_rate = mean(Employed, na.rm = TRUE), n = n(), .groups = "drop")
  print(did_table)
  
  # ── 2. Employed variable distribution ────────────────────────────────────
  message("=== Employed variable counts ===")
  print(cleaned_df %>% count(Employed))
  
  # ── 3. Parallel trends — event-study plot ────────────────────────────────
  # Pre-2021 interaction coefficients should be flat if parallel trends holds.
  message("=== Pre-trend test (event study) ===")
  df_pt <- cleaned_df %>%
    mutate(ShnatSeker = factor(ShnatSeker, levels = c(2019, 2017, 2018, 2021, 2022, 2023)))
  
  reg_pretrend <- feols(
    Employed ~ Mother + i(ShnatSeker, Mother, ref = 2019) +
      MatzavMishpachti + Dat + TeudaGvoha + GilNK + MachozMegurim + MisparHorimYechidim,
    data = df_pt, cluster = ~IDPUF
  )
  iplot(reg_pretrend, main = "Event-study: Mother x Year (ref = 2019)")
  
  # ── 4. Missing-value audit ────────────────────────────────────────────────
  message("=== NA counts for regression variables ===")
  na_summary <- cleaned_df %>%
    select(Employed, Mother, Post, MatzavMishpachti, Dat, GilNK,
           MachozMegurim, TeudaGvoha, MisparHorimYechidim) %>%
    summarise(across(everything(), ~sum(is.na(.))))
  print(na_summary)
  
  # ── 5. Are missings on Employed systematic? ───────────────────────────────
  message("=== Missingness pattern for Employed ===")
  miss_pattern <- cleaned_df %>%
    mutate(emp_missing = is.na(Employed)) %>%
    group_by(emp_missing) %>%
    summarise(
      pct_mother = mean(Mother, na.rm = TRUE),
      mean_age   = mean(GilNK, na.rm = TRUE),
      n          = n(),
      .groups    = "drop"
    )
  print(miss_pattern)
  
  # ── 6. Peek at rows where Employed is NA ─────────────────────────────────
  message("=== Sample rows with Employed = NA ===")
  cleaned_df %>%
    filter(is.na(Employed)) %>%
    select(
      ShnatSeker, Oved35Shaot, MisraMelea, SibaLeAvodaChelkit,
      AvadShanaAchrona, KamaChodashimAvadBashana, SibaLoAvadHashana,
      ShaotAvodaBederechKlalNK, MachozYishuvAvoda, Muasak,
      ShaotIkarit, AvodaMeHaBayit, AvadMeHaBayit, KamaShaot, Employed
    ) %>%
    head(20) %>%
    print(width = Inf)
  
  invisible(list(
    did_table   = did_table,
    na_summary  = na_summary,
    miss_pattern = miss_pattern,
    pretrend_model = reg_pretrend
  ))
}