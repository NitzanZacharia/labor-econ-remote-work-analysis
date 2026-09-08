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
  # i(ShnatSeker, ref = 2019) supplies the year main effects for the Post=0
  # group; without it, non-mothers' year-to-year variation is unmodeled and
  # the Mother:year coefficients below conflate the mother-specific deviation
  # with the common year trend. ref = 2019 (not factor level order) is what
  # sets the omitted reference period in both i() terms.
  message("=== Pre-trend test (event study) ===")

  reg_pretrend <- feols(
    as.formula(paste(
      "Employed ~ Mother + i(ShnatSeker, ref = 2019) + i(ShnatSeker, Mother, ref = 2019) +",
      paste(DEFAULT_CONTROLS, collapse = " + ")
    )),
    data = cleaned_df, cluster = ~IDPUF
  )
  pretrend_table <- etable(reg_pretrend, digits = 4)
  print(pretrend_table)
  # Draws to whatever graphics device is already active -- deliberately no dev.new()/dev.off()
  # here. dev.new() unconditionally opens a NEW top-level device regardless of context, which is
  # what caused every headless `Rscript main.R` run to leak an auto-numbered Rplots*.pdf into the
  # repo root (R falls back to a default pdf() device when no interactive one is available, and
  # nothing ever closed it). Device management belongs to the caller, matching how the test suite
  # already handles this (see helper-setup.R's with_null_device()) -- main.R wraps this call in an
  # explicit device targeting outputs/; tests wrap it in a null device.
  tryCatch({
    iplot(reg_pretrend, main = "Event-study: Mother x Year (ref = 2019)")
  }, error = function(e) {
    message("iplot failed: ", e$message)
  })
  
  # ── 4. Missing-value audit ────────────────────────────────────────────────
  message("=== NA counts for regression variables ===")
  na_summary <- cleaned_df %>%
    select(Employed, Mother, Post, MatzavMishpachti, Dat, GilNK,
           MachozMegurim, TeudaGvoha) %>%
    summarise(across(everything(), ~sum(is.na(.))))
  print(na_summary)
  
  # ── 5. Are missings on Employed systematic? ───────────────────────────────
  message("=== Missingness pattern for Employed ===")
  miss_pattern <- cleaned_df %>%
    mutate(emp_missing = is.na(Employed)) %>%
    group_by(emp_missing) %>%
    summarise(
      pct_mother = mean(Mother, na.rm = TRUE),
      mean_age   = mean(as.numeric(as.character(GilNK)), na.rm = TRUE),
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
    pretrend_table = pretrend_table,
    pretrend_model = reg_pretrend
  ))
}