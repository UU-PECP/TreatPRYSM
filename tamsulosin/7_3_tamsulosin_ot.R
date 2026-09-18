library(haven)
library(lubridate)
library(MatchIt)
library(data.table)
library(dplyr)
library(ggplot2)
library(scales)
library(survival)
library(survminer)
library(tableone)

## ============================================================
##  Read the on-treatment interval dataset (from File 7.1 + 7.2)
## ============================================================
df <- read_sas('F://Users//Wyatt003//Tamsulosin//Output//bph_ot_test.sas7bdat')
sapply(df, class)

setwd("F:\\Users\\Wyatt003\\Tamsulosin\\Results")
## Exposure coding: 1 = tamsulosin, 2 = alfuzosin, 3 = finasteride
## Explicit binary exposure: tamsulosin vs comparator
df$tamsulosin <- ifelse(df$index_exposure == 1, 1, 0)

## On-treatment end of follow-up

df <- df %>% 
  filter(interval_window_start > lubridate::ymd('2002-10-31')) %>% 
  filter(interval_window_start < end_of_fu)  %>%
  mutate(fu_days = ymd(end_of_fu) - ymd(interval_window_start))




###############################
# RUN OT ANALYSIS #
###############################

 run_ot_analysis <- function(df, ref_code, tag) {

  ## keep only tamsulosin (1) and the chosen referent
  d <- df %>% filter(index_exposure == 1 | index_exposure == ref_code)

  ## ---- drop variables no longer needed ----
  d <- d %>%
    select(-last_coverage_period_start, -last_coverage_period_end, -aSAH_apc_dt,
           -days_since_last_treatment, -index_exposure)

  ## ---- patient-level collapse for crude incidence / KM ----
  individual_data <- d %>%
    group_by(patid) %>%
    summarise(
      tamsulosin = min(tamsulosin),
      index_date = min(index_date),
      end_of_fu  = min(end_of_fu),
      fu_days    = min(fu_days),
      aSAH       = max(aSAH_within_interval),
      .groups = "drop"
    )

  ## ---- incidence rates ----
  summary_data <- individual_data %>%
    group_by(tamsulosin) %>%
    summarise(
      total_cases           = sum(aSAH),
      total_follow_up       = sum(fu_days),
      total_follow_up_years = sum(fu_days) / 365.25,
      median_fu_days        = median(fu_days),
      .groups = "drop"
    ) %>%
    mutate(incidence_rate = (total_cases / as.numeric(total_follow_up_years)) * 1000)

  print(summary_data)
  sink(paste0("tamsulosin_ot_incidence_", tag, ".txt"))
  print(summary_data)
  sink()
 

  ## ---- crude Cox (patient level) ----
  cox_model <- coxph(Surv(time = fu_days, event = aSAH) ~ tamsulosin,
                     data = individual_data)
  sink(paste0("tamsulosin_ot_cox_", tag, ".txt"))
  print(summary(cox_model))
  sink()

  ###
  
   ## ---- Kaplan-Meier ----
   surv_fit <- survfit(Surv(fu_days, aSAH) ~ tamsulosin, data = individual_data)
   
   gg_crude <- ggsurvplot(
     surv_fit,
     fun = "event", conf.int = TRUE, censor = FALSE, break.time.by = 365,
     xlab = "Follow-up (days)", ylab = "Cumulative incidence of aSAH",
     legend.labs = c(if (ref_code == 2) "Alfuzosin" else "Finasteride", "Tamsulosin"),
     palette = c("#1b9e77", "#d95f02"),
     ggtheme = theme_minimal(base_size = 12),
     risk.table = TRUE, risk.table.height = 0.25,
     risk.table.y.text.col = TRUE, ylim = c(0, 0.01)
   )
   gg_crude$plot <- gg_crude$plot +
     scale_y_continuous(labels = scales::percent_format(accuracy = 0.01),
                        breaks = seq(0, 1, 0.0005))
   ggsave(paste0("tamsulosin_ot_km_", tag, ".png"),
          plot = gg_crude$plot, width = 8, height = 6, dpi = 300)

  ## ============================================================
  ##  Time-varying confounder plot: BMI over time
  ##  (replaces Jos's blood-pressure plot; smoking is categorical
  ##   so it's carried into the model rather than plotted here)
  ## ============================================================

  ## fill missing BMI by per-patient median (keep NA if all missing)
  d_filled <- d %>%
    group_by(patid) %>%
    mutate(across(bmi_value,
                  ~ ifelse(is.na(.x),
                           ifelse(is.nan(median(.x, na.rm = TRUE)), NA,
                                  median(.x, na.rm = TRUE)),
                           .x))) %>%
    ungroup()

  ## ever-aSAH flag (patient level)
  d_filled <- d_filled %>%
    group_by(patid) %>%
    mutate(ever_aSAH = any(aSAH_within_interval == 1)) %>%
    ungroup()

  bmi_vars <- c("patid", "interval_window_start", "tamsulosin", "index_date",
                "interval_window_end", "ever_aSAH", "bmi_value")
  df_bmi <- d_filled %>% select(all_of(bmi_vars)) %>%
    mutate(
      t_months_start = as.numeric(interval_window_start - index_date) / 30,
      tamsulosin_lbl = factor(tamsulosin, labels = c("No", "Yes")),
      outcome_lbl    = if_else(ever_aSAH, "Ever aSAH", "No aSAH")
    )

  setDT(df_bmi)
  df_int <- df_bmi[ , .(bmi_value = mean(bmi_value, na.rm = TRUE)),
                    by = .(patid, t_months_start, tamsulosin_lbl, outcome_lbl)]

  median_hilow <- function(x, ...) {
    qs <- quantile(x, c(.025, .5, .975), na.rm = TRUE)
    names(qs) <- c("ymin", "y", "ymax"); qs
  }

  bmi_plot <- ggplot(df_int,
                     aes(x = t_months_start, y = bmi_value,
                         colour = tamsulosin_lbl,
                         group = tamsulosin_lbl)) +
    stat_summary(fun.data = median_hilow, geom = "smooth",
                 linewidth = 0.8, alpha = 0.2, se = TRUE, span = 0.4) +
    facet_wrap(~ outcome_lbl) +
    labs(x = "Months since index date", y = "BMI (kg/m2)",
         colour = "On Tamsulosin?") +
    scale_colour_brewer(palette = "Set1") +
    theme_bw()

  ggsave(paste0("tamsulosin_ot_bmi_", tag, ".png"),
         plot = bmi_plot, width = 8, height = 6, dpi = 300)

  ## ============================================================
  ##  Counting-process Cox with time-varying recency + confounders
  ## ============================================================
  keep <- c("patid",
            "interval_window_start", "interval_window_end", "index_date",
            "aSAH_within_interval",
            "treatment_recency_status",
            "tamsulosin",
            "bmi_value", "smk_cur", "smk_ex", "smk_non",   # time-varying confounders
            "age_at_interval_start")

  setDT(d_filled)[ , (setdiff(names(d_filled), keep)) := NULL ]

  df_cox <- copy(d_filled)[ , `:=`(
    tstart  = as.numeric(interval_window_start - index_date),
    tstop   = as.numeric(interval_window_end   - index_date),
    rec_fac = factor(treatment_recency_status,
                     levels = c("Past", "Recent", "Current"))
    # ses_i   = as.integer(factor(deprivation_decile))
  )][ , c("interval_window_start", "interval_window_end",
          "index_date", "treatment_recency_status"
          #,"deprivation_decile"
          ) := NULL ]

  setorder(df_cox, tstop)

  cox_fit <- coxph(
    Surv(tstart, tstop, aSAH_within_interval) ~
      relevel(rec_fac, ref = "Past") +
      tamsulosin +
      bmi_value + smk_cur + smk_ex +        # smk_non is the reference smoking level
      age_at_interval_start,
    data    = df_cox,
    cluster = patid,
    ties    = "breslow",
    x = FALSE, y = FALSE, model = FALSE,
    robust  = TRUE,
    control = coxph.control(timefix = FALSE, iter.max = 20)
  )

  sink(paste0("tamsulosin_ot_recency_", tag, ".txt"))
  print(summary(cox_fit))
  sink()

  invisible(list(incidence = summary_data, cox = cox_fit))
 }

## ============================================================
##  Run both referent models
## ============================================================
alf_results <- run_ot_analysis(df, ref_code = 2, tag = "alfuzosin")
fin_results <- run_ot_analysis(df, ref_code = 3, tag = "finasteride")
