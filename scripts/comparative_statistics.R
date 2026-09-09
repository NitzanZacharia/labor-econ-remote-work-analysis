# comparative_statistics.R
# Descriptive / comparative statistics requested by the supervising professor:
# missingness audit, an employment-variable audit (Muasak vs. Employed vs. hours),
# employment averages for mothers vs. non-mothers, and work-mobility trends over
# time (mothers of young children vs. others). Not used as regression input.
library(tidyverse)

run_comparative_stats <- function(cleaned_df) {

  analysis_vars <- c(
    "Employed", "Mother", "Post", "WFH", "WorkHoursCont",
    "MatzavMishpachti", "Dat", "GilNK", "MachozMegurim", "TeudaGvoha",
    "BirthContinent", "WorksOutsideLocality"
  )

  # ── 1. Missingness table ───────────────────────────────────────────────────
  message("=== Percent missing, by variable ===")
  missing_pct <- cleaned_df %>%
    summarise(across(all_of(analysis_vars), ~ mean(is.na(.)) * 100)) %>%
    pivot_longer(everything(), names_to = "variable", values_to = "pct_missing") %>%
    arrange(desc(pct_missing))
  print(missing_pct)

  # ── 2. Employment-variable audit ───────────────────────────────────────────
  # Multiple raw/derived fields relate to "employment" — show them side by side
  # before relying on the single collapsed Employed variable used in the models.
  message("=== Muasak (raw employment status) breakdown ===")
  print(cleaned_df %>% count(Muasak, name = "n") %>% mutate(pct = n / sum(n) * 100))

  message("=== Employed (collapsed Y variable) breakdown ===")
  print(cleaned_df %>% count(Employed, name = "n") %>% mutate(pct = n / sum(n) * 100))

  message("=== WorkHoursCont summary, among Employed == 1 ===")
  print(cleaned_df %>% filter(Employed == 1) %>% summarise(
    n      = sum(!is.na(WorkHoursCont)),
    mean   = mean(WorkHoursCont, na.rm = TRUE),
    median = median(WorkHoursCont, na.rm = TRUE),
    sd     = sd(WorkHoursCont, na.rm = TRUE)
  ))

  # ── 3. Employment averages: mothers vs. non-mothers ────────────────────────
  message("=== Employment rate: mothers vs. non-mothers ===")
  emp_by_mother <- cleaned_df %>%
    group_by(Mother) %>%
    summarise(emp_rate = mean(Employed, na.rm = TRUE), n = n(), .groups = "drop")
  print(emp_by_mother)

  # ── 4. Work mobility over time: mothers vs. non-mothers ────────────────────
  message("=== Share working outside locality of residence, by year x Mother ===")
  mobility_by_year <- cleaned_df %>%
    group_by(ShnatSeker, Mother) %>%
    summarise(
      pct_outside = mean(WorksOutsideLocality, na.rm = TRUE) * 100,
      n           = sum(!is.na(WorksOutsideLocality)),
      .groups     = "drop"
    ) %>%
    mutate(MotherLabel = if_else(Mother == 1, "Mothers", "Non-mothers"))
  print(mobility_by_year)

  p_mobility <- ggplot(
    mobility_by_year,
    aes(x = ShnatSeker, y = pct_outside, colour = MotherLabel, group = MotherLabel)
  ) +
    geom_line(linewidth = 0.9) +
    geom_point(size = 2.2) +
    scale_colour_manual(values = c("Mothers" = "#D85A30", "Non-mothers" = "#378ADD")) +
    scale_x_continuous(breaks = sort(unique(mobility_by_year$ShnatSeker))) +
    labs(
      title    = "Share working outside locality of residence, over time",
      subtitle = "Women aged 25–59, by mother status",
      x        = "Survey year",
      y        = "% working outside residence locality",
      colour   = NULL,
      caption  = "2020 excluded from the survey years analyzed."
    ) +
    theme_minimal(base_size = 12) +
    theme(
      plot.title      = element_text(size = 13, face = "bold"),
      plot.subtitle   = element_text(size = 10, colour = "grey40"),
      legend.position = "top",
      panel.grid.minor = element_blank()
    )
  print(p_mobility)

  invisible(list(
    missing_pct       = missing_pct,
    emp_by_mother     = emp_by_mother,
    mobility_by_year  = mobility_by_year,
    plots             = list(mobility = p_mobility)
  ))
}
