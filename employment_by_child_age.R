# employment_by_child_age.R
# Analyses employment rates for mothers by age group of their youngest child.
# GilYeledTzairMBNK coding: 0 = no children, 1 = age 0–1, 2 = age 2–4,
#                            3 = age 5–9, 4 = age 10–14, 5 = age 15–17
library(tidyverse)
library(fixest)

employment_by_child_age <- function(cleaned_df) {
  
  # ── 1. Prepare youngest-child age variable ───────────────────────────────
  # GilYeledTzairMBNK is already a categorical code:
  #   0 = no children, 1 = age 0–1, 2 = age 2–4,
  #   3 = age 5–9,     4 = age 10–14, 5 = age 15–17
  # Restrict to mothers (Mother == 1) with a valid code (1–5)
  child_age_labels <- c(
    "1" = "0–1",
    "2" = "2–4",
    "3" = "5–9",
    "4" = "10–14",
    "5" = "15–17"
  )
  
  df_mothers <- cleaned_df %>%
    filter(
      Mother == 1,
      !is.na(GilYeledTzairMBNK),
      GilYeledTzairMBNK %in% 1:5,      # exclude code 0 (no children)
      !is.na(Employed)
    ) %>%
    mutate(
      ChildAgeBin = factor(
        GilYeledTzairMBNK,
        levels = 1:5,
        labels = child_age_labels
      )
    )
  
  # ── 2. Raw employment rates by child-age bin ─────────────────────────────
  message("=== Raw employment rates by youngest-child age ===")
  emp_raw <- df_mothers %>%
    group_by(ChildAgeBin) %>%
    summarise(
      emp_rate = mean(Employed, na.rm = TRUE),
      n        = n(),
      .groups  = "drop"
    )
  print(emp_raw)
  
  # ── 3. Pre/Post breakdown ────────────────────────────────────────────────
  message("=== Employment rates by youngest-child age × Pre/Post ===")
  emp_by_period <- df_mothers %>%
    group_by(ChildAgeBin, Post) %>%
    summarise(
      emp_rate = mean(Employed, na.rm = TRUE),
      n        = n(),
      .groups  = "drop"
    ) %>%
    mutate(Period = if_else(Post == 1, "Post-2021", "Pre-2021"))
  print(emp_by_period)
  
  # ── 4. Regression: employment ~ child-age bin (with controls) ───────────
  controls <- c(
    "MatzavMishpachti",
    "Dat",
    "GilNK",
    "MachozMegurim",
    "TeudaGvoha",
    "MisparHorimYechidim"
  )
  
  formula_age <- as.formula(paste(
    "Employed ~ ChildAgeBin",
    paste(controls, collapse = " + "),
    sep = " + "
  ))
  
  reg_age <- feols(formula_age, data = df_mothers, cluster = ~IDPUF)
  
  message("=== Regression: employment ~ youngest-child age (controlled) ===")
  print(etable(reg_age, digits = 4))
  
  # ── 5. Adjusted employment rates (margins from regression) ──────────────
  # Predict employment probability at each bin, holding controls at means
  pred_df <- df_mothers %>%
    group_by(ChildAgeBin) %>%
    slice(1) %>%                     # one row per bin
    ungroup() %>%
    mutate(across(all_of(controls), ~mean(df_mothers[[cur_column()]], na.rm = TRUE)))
  
  pred_df$adj_emp <- predict(reg_age, newdata = pred_df)
  
  # Merge raw n back in for label annotation
  plot_df <- emp_raw %>%
    left_join(
      pred_df %>% select(ChildAgeBin, adj_emp),
      by = "ChildAgeBin"
    )
  
  # ── 6. Plot ──────────────────────────────────────────────────────────────
  
  # 6a. Raw employment rate by child-age bin
  p_raw <- ggplot(emp_raw, aes(x = ChildAgeBin, y = emp_rate)) +
    geom_col(fill = "#1D9E75", alpha = 0.85, width = 0.65) +
    geom_text(
      aes(label = paste0(round(emp_rate * 100, 1), "%")),
      vjust = -0.5, size = 3.2, colour = "#2C2C2A"
    ) +
    geom_text(
      aes(label = paste0("n=", scales::comma(n))),
      vjust = 1.6, size = 2.8, colour = "#5F5E5A"
    ) +
    scale_y_continuous(
      labels = scales::percent_format(accuracy = 1),
      limits = c(0, max(emp_raw$emp_rate) * 1.12),
      expand = expansion(mult = c(0, 0.02))
    ) +
    labs(
      title    = "Employment rate by age of youngest child",
      subtitle = "Mothers aged 25–59, survey years 2017–2023 (excl. 2020)",
      x        = "Age group of youngest child",
      y        = "Employment rate",
      caption  = "Source: LFS data. Bars show raw employment rates; n = cell size."
    ) +
    theme_minimal(base_size = 12) +
    theme(
      plot.title       = element_text(size = 13, face = "bold"),
      plot.subtitle    = element_text(size = 10, colour = "grey40"),
      axis.title       = element_text(size = 10),
      panel.grid.major.x = element_blank(),
      panel.grid.minor   = element_blank()
    )
  
  # 6b. Pre vs Post comparison (line chart)
  p_period <- ggplot(
    emp_by_period,
    aes(x = ChildAgeBin, y = emp_rate, colour = Period, group = Period)
  ) +
    geom_line(linewidth = 0.9) +
    geom_point(size = 2.5) +
    scale_colour_manual(values = c("Pre-2021" = "#378ADD", "Post-2021" = "#D85A30")) +
    scale_y_continuous(
      labels = scales::percent_format(accuracy = 1),
      limits = c(
        min(emp_by_period$emp_rate) * 0.92,
        max(emp_by_period$emp_rate) * 1.06
      )
    ) +
    labs(
      title    = "Employment rate by youngest-child age: Pre vs Post-2021",
      subtitle = "Mothers aged 25–59",
      x        = "Age group of youngest child",
      y        = "Employment rate",
      colour   = NULL,
      caption  = "Post-2021 covers 2021–2023; Pre-2021 covers 2017–2019."
    ) +
    theme_minimal(base_size = 12) +
    theme(
      plot.title         = element_text(size = 13, face = "bold"),
      plot.subtitle      = element_text(size = 10, colour = "grey40"),
      axis.title         = element_text(size = 10),
      legend.position    = "top",
      panel.grid.minor   = element_blank()
    )
  
  # 6c. Raw vs adjusted side-by-side
  p_adj <- plot_df %>%
    pivot_longer(cols = c(emp_rate, adj_emp),
                 names_to = "type", values_to = "rate") %>%
    mutate(type = recode(type,
                         emp_rate = "Raw",
                         adj_emp  = "Adjusted (controls)")) %>%
    ggplot(aes(x = ChildAgeBin, y = rate, fill = type)) +
    geom_col(position = position_dodge(width = 0.7), width = 0.6, alpha = 0.85) +
    scale_fill_manual(values = c("Raw" = "#1D9E75", "Adjusted (controls)" = "#7F77DD")) +
    scale_y_continuous(
      labels = scales::percent_format(accuracy = 1),
      expand = expansion(mult = c(0, 0.05))
    ) +
    labs(
      title    = "Raw vs adjusted employment rate by youngest-child age",
      subtitle = "Controls: marital status, religiosity, age group, district, education, single-parent status",
      x        = "Age group of youngest child",
      y        = "Employment rate",
      fill     = NULL,
      caption  = "Adjusted rates: OLS predictions with controls held at sample means."
    ) +
    theme_minimal(base_size = 12) +
    theme(
      plot.title         = element_text(size = 13, face = "bold"),
      plot.subtitle      = element_text(size = 9.5, colour = "grey40"),
      axis.title         = element_text(size = 10),
      legend.position    = "top",
      panel.grid.major.x = element_blank(),
      panel.grid.minor   = element_blank()
    )
  
  # ── 7. Print plots ───────────────────────────────────────────────────────
  print(p_raw)
  print(p_period)
  print(p_adj)
  
  # ── 8. Return results invisibly ─────────────────────────────────────────
  invisible(list(
    emp_raw      = emp_raw,
    emp_by_period = emp_by_period,
    model        = reg_age,
    plots        = list(raw = p_raw, period = p_period, adjusted = p_adj)
  ))
}