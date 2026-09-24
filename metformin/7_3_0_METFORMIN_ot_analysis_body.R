## the Treat-PRYSM project
## Drug - Metformin
##
## File 7_3_0: On-treatment analysis - SHARED BODY
## Modelled on tamsulosin/7_3_tamsulosin_ot.R, with one structural change:
##
## tamsulosin/7_3's Cox model includes "tamsulosin" (index-drug indicator)
## and "rec_fac" (recency of the patient's own index drug) as two SEPARATE
## additive terms. That only recovers the marginal effect of each, not a
## direct contrast of e.g. "current tamsulosin vs. current comparator" -
## for that you'd need an interaction, which isn't in the tamsulosin
## script. Since the metformin protocol explicitly asks for current/
## recent/past index-drug use to each be compared against a single
## "current comparator" reference category, this instead builds ONE
## combined 4-level factor (Comparator / Index-Current / Index-Recent /
## Index-Past) with "Comparator" as the reference level, which directly
## gives each of those three contrasts as a single coefficient - no
## interaction term needed, and it matches the protocol's stated
## comparisons more directly than the tamsulosin script's two-term setup.
##
## source() this from a per-cohort driver (7_3/7_4) that has already set
## the variables below. Do not run this file directly.
##
## Required variables from the driver:
##   cohort_label     - e.g. "su" / "sglt2i"
##   comparator_name   - e.g. "Sulphonylureas" / "SGLT2 inhibitors"
##   ot_sas_path        - path to output.<cohort>_ot_bmi_smk_age.sas7bdat (7_0 output)
##   study_start_date   - character "YYYY-MM-DD", cohort study start (filters spurious pre-study intervals)
##   results_dir         - directory to write outputs into

library(haven)
library(lubridate)
library(data.table)
library(dplyr)
library(ggplot2)
library(scales)
library(survival)
library(survminer)
library(tableone)

df <- read_sas(ot_sas_path)
sapply(df, class)

setwd(results_dir)

## Exposure coding: 1 = metformin, 2 = comparator
df$metformin <- ifelse(df$index_exposure == 1, 1, 0)

## NOTE: fu_days already comes in from SAS (7_0, Step: end_of_fu - index_date + 1)
## as a per-patient total follow-up duration - do not overwrite it here with a
## per-interval quantity, or individual_data's collapse further down will pick
## up "time remaining from this interval to end of follow-up" instead of total
## follow-up from index date.
## On-treatment end of follow-up
df <- df %>%
  filter(interval_window_start > lubridate::ymd(study_start_date)) %>%
  filter(interval_window_start < end_of_fu)

###############################
# RUN OT ANALYSIS #
###############################

run_ot_analysis <- function(df) {

  d <- df

  ## ---- patient-level collapse for crude incidence / KM ----
  individual_data <- d %>%
    group_by(patid) %>%
    summarise(
      metformin  = min(metformin),
      index_date = min(index_date),
      end_of_fu  = min(end_of_fu),
      fu_days    = min(fu_days),
      aSAH       = max(aSAH_within_interval),
      .groups = "drop"
    )

  ## ---- incidence rates ----
  summary_data <- individual_data %>%
    group_by(metformin) %>%
    summarise(
      total_cases           = sum(aSAH),
      total_follow_up       = sum(fu_days),
      total_follow_up_years = sum(fu_days) / 365.25,
      median_fu_days        = median(fu_days),
      .groups = "drop"
    ) %>%
    mutate(incidence_rate = (total_cases / as.numeric(total_follow_up_years)) * 1000)

  print(summary_data)
  sink(paste0("metformin_", cohort_label, "_ot_incidence.txt"))
  print(summary_data)
  sink()

  ## ---- crude Cox (patient level) ----
  cox_model <- coxph(Surv(time = fu_days, event = aSAH) ~ metformin,
                     data = individual_data)
  sink(paste0("metformin_", cohort_label, "_ot_cox.txt"))
  print(summary(cox_model))
  sink()

  ## ---- Kaplan-Meier ----
  surv_fit <- survfit(Surv(fu_days, aSAH) ~ metformin, data = individual_data)

  gg_crude <- ggsurvplot(
    surv_fit,
    data = individual_data,
    fun = "event", conf.int = TRUE, censor = FALSE, break.time.by = 365,
    xlab = "Follow-up (days)", ylab = "Cumulative incidence of aSAH",
    legend.labs = c(comparator_name, "Metformin"),
    palette = c("#1b9e77", "#d95f02"),
    ggtheme = theme_minimal(base_size = 12),
    risk.table = TRUE, risk.table.height = 0.25,
    risk.table.y.text.col = TRUE, ylim = c(0, 0.01)
  )
  gg_crude$plot <- gg_crude$plot +
    scale_y_continuous(labels = scales::percent_format(accuracy = 0.01),
                       breaks = seq(0, 1, 0.0005))
  ggsave(paste0("metformin_", cohort_label, "_ot_km.png"),
         plot = gg_crude$plot, width = 8, height = 6, dpi = 300)

  ## ============================================================
  ##  Time-varying confounder plot: BMI over time
  ## ============================================================

  d_filled <- d %>%
    group_by(patid) %>%
    mutate(across(bmi_value,
                  ~ ifelse(is.na(.x),
                           ifelse(is.nan(median(.x, na.rm = TRUE)), NA,
                                  median(.x, na.rm = TRUE)),
                           .x))) %>%
    ungroup()

  d_filled <- d_filled %>%
    group_by(patid) %>%
    mutate(ever_aSAH = any(aSAH_within_interval == 1)) %>%
    ungroup()

  bmi_vars <- c("patid", "interval_window_start", "metformin", "index_date",
                "interval_window_end", "ever_aSAH", "bmi_value")
  df_bmi <- d_filled %>% select(all_of(bmi_vars)) %>%
    mutate(
      t_months_start = as.numeric(interval_window_start - index_date) / 30,
      metformin_lbl = factor(metformin, labels = c("No", "Yes")),
      outcome_lbl    = if_else(ever_aSAH, "Ever aSAH", "No aSAH")
    )

  setDT(df_bmi)
  df_int <- df_bmi[ , .(bmi_value = mean(bmi_value, na.rm = TRUE)),
                    by = .(patid, t_months_start, metformin_lbl, outcome_lbl)]

  median_hilow <- function(x, ...) {
    qs <- quantile(x, c(.025, .5, .975), na.rm = TRUE)
    names(qs) <- c("ymin", "y", "ymax"); qs
  }

  bmi_plot <- ggplot(df_int,
                     aes(x = t_months_start, y = bmi_value,
                         colour = metformin_lbl,
                         group = metformin_lbl)) +
    stat_summary(fun.data = median_hilow, geom = "smooth",
                 linewidth = 0.8, alpha = 0.2, se = TRUE, span = 0.4) +
    facet_wrap(~ outcome_lbl) +
    labs(x = "Months since index date", y = "BMI (kg/m2)",
         colour = "On metformin?") +
    scale_colour_brewer(palette = "Set1") +
    theme_bw()

  ggsave(paste0("metformin_", cohort_label, "_ot_bmi.png"),
         plot = bmi_plot, width = 8, height = 6, dpi = 300)

  ## ============================================================
  ##  Counting-process Cox: main recency model
  ##  (Comparator / Index-Current / Index-Recent / Index-Past)
  ## ============================================================
  d_filled <- d_filled %>%
    mutate(exposure_status = case_when(
      metformin == 0 ~ "Comparator",
      metformin == 1 & treatment_recency_status == "Current" ~ "Index-Current",
      metformin == 1 & treatment_recency_status == "Recent"  ~ "Index-Recent",
      metformin == 1 & treatment_recency_status == "Past"    ~ "Index-Past",
      TRUE ~ NA_character_
    ))

  keep <- c("patid",
            "interval_window_start", "interval_window_end", "index_date",
            "aSAH_within_interval",
            "exposure_status", "dose_category", "duration_category",
            "release_pattern_current",
            "bmi_value", "smk_cur", "smk_ex", "smk_non",
            "gender", "age_at_interval_start")

  d_cox_src <- d_filled[, keep]
  setDT(d_cox_src)

  df_cox <- copy(d_cox_src)[ , `:=`(
    tstart  = as.numeric(interval_window_start - index_date),
    tstop   = as.numeric(interval_window_end   - index_date),
    exposure_fac = factor(exposure_status,
                     levels = c("Comparator", "Index-Past", "Index-Recent", "Index-Current"))
  )][ , c("interval_window_start", "interval_window_end",
          "index_date", "exposure_status") := NULL ]

  setorder(df_cox, tstop)

  cox_fit <- coxph(
    Surv(tstart, tstop, aSAH_within_interval) ~
      relevel(exposure_fac, ref = "Comparator") +
      gender + bmi_value + smk_cur + smk_ex +        # smk_non is the reference smoking level
      age_at_interval_start,
    data    = df_cox,
    cluster = patid,
    ties    = "breslow",
    x = FALSE, y = FALSE, model = FALSE,
    robust  = TRUE,
    control = coxph.control(timefix = FALSE, iter.max = 20)
  )

  sink(paste0("metformin_", cohort_label, "_ot_recency.txt"))
  print(summary(cox_fit))
  sink()

  ## ============================================================
  ##  Secondary model: daily dose (Comparator / Low / High), among
  ##  intervals currently on the index drug - per protocol, dose is
  ##  only meaningful while actively on treatment.
  ## ============================================================
  d_dose <- d_filled %>%
    mutate(dose_status = case_when(
      metformin == 0 ~ "Comparator",
      metformin == 1 & treatment_recency_status == "Current" & dose_category == "Low"  ~ "Current-Low",
      metformin == 1 & treatment_recency_status == "Current" & dose_category == "High" ~ "Current-High",
      TRUE ~ NA_character_
    )) %>%
    filter(!is.na(dose_status))

  df_dose <- copy(setDT(d_dose[, c(keep, "index_date", "interval_window_start", "interval_window_end", "dose_status")]))[, `:=`(
    tstart = as.numeric(interval_window_start - index_date),
    tstop  = as.numeric(interval_window_end - index_date),
    dose_fac = factor(dose_status, levels = c("Comparator", "Current-Low", "Current-High"))
  )]
  setorder(df_dose, tstop)

  cox_dose <- coxph(
    Surv(tstart, tstop, aSAH_within_interval) ~
      relevel(dose_fac, ref = "Comparator") +
      gender + bmi_value + smk_cur + smk_ex + age_at_interval_start,
    data = df_dose, cluster = patid, ties = "breslow",
    robust = TRUE, control = coxph.control(timefix = FALSE, iter.max = 20)
  )
  sink(paste0("metformin_", cohort_label, "_ot_dose.txt"))
  print(summary(cox_dose))
  sink()

  ## ============================================================
  ##  Secondary model: continuous duration (Comparator / <1yr / >=1yr),
  ##  among intervals currently on the index drug.
  ## ============================================================
  d_dur <- d_filled %>%
    mutate(duration_status = case_when(
      metformin == 0 ~ "Comparator",
      metformin == 1 & treatment_recency_status == "Current" & duration_category == "<1yr"  ~ "Current-Short",
      metformin == 1 & treatment_recency_status == "Current" & duration_category == ">=1yr" ~ "Current-Long",
      TRUE ~ NA_character_
    )) %>%
    filter(!is.na(duration_status))

  df_dur <- copy(setDT(d_dur[, c(keep, "index_date", "interval_window_start", "interval_window_end", "duration_status")]))[, `:=`(
    tstart = as.numeric(interval_window_start - index_date),
    tstop  = as.numeric(interval_window_end - index_date),
    duration_fac = factor(duration_status, levels = c("Comparator", "Current-Short", "Current-Long"))
  )]
  setorder(df_dur, tstop)

  cox_duration <- coxph(
    Surv(tstart, tstop, aSAH_within_interval) ~
      relevel(duration_fac, ref = "Comparator") +
      gender + bmi_value + smk_cur + smk_ex + age_at_interval_start,
    data = df_dur, cluster = patid, ties = "breslow",
    robust = TRUE, control = coxph.control(timefix = FALSE, iter.max = 20)
  )
  sink(paste0("metformin_", cohort_label, "_ot_duration.txt"))
  print(summary(cox_duration))
  sink()

  ## ============================================================
  ##  Secondary model: release pattern / formulation (Comparator /
  ##  Standard tablet / Slow-release tablet / Oral solution / Oral
  ##  suspension), among intervals currently on metformin - the
  ##  comparator's own formulation is never resolved, so every
  ##  comparator interval collapses into "Comparator" regardless,
  ##  same as the dose/duration models above.
  ## ============================================================
  d_release <- d_filled %>%
    mutate(release_status = case_when(
      metformin == 0 ~ "Comparator",
      metformin == 1 & treatment_recency_status == "Current" & release_pattern_current == "Standard tablet"     ~ "Current-StandardTablet",
      metformin == 1 & treatment_recency_status == "Current" & release_pattern_current == "Slow-release tablet" ~ "Current-SlowRelease",
      metformin == 1 & treatment_recency_status == "Current" & release_pattern_current == "Oral solution"       ~ "Current-OralSolution",
      metformin == 1 & treatment_recency_status == "Current" & release_pattern_current == "Oral suspension"     ~ "Current-OralSuspension",
      TRUE ~ NA_character_
    )) %>%
    filter(!is.na(release_status))

  df_release <- copy(setDT(d_release[, c(keep, "index_date", "interval_window_start", "interval_window_end", "release_status")]))[, `:=`(
    tstart = as.numeric(interval_window_start - index_date),
    tstop  = as.numeric(interval_window_end - index_date),
    release_fac = factor(release_status, levels = c("Comparator", "Current-StandardTablet", "Current-SlowRelease", "Current-OralSolution", "Current-OralSuspension"))
  )]
  setorder(df_release, tstop)

  cox_release <- coxph(
    Surv(tstart, tstop, aSAH_within_interval) ~
      relevel(release_fac, ref = "Comparator") +
      gender + bmi_value + smk_cur + smk_ex + age_at_interval_start,
    data = df_release, cluster = patid, ties = "breslow",
    robust = TRUE, control = coxph.control(timefix = FALSE, iter.max = 20)
  )
  sink(paste0("metformin_", cohort_label, "_ot_release.txt"))
  print(summary(cox_release))
  sink()

  invisible(list(incidence = summary_data, cox_recency = cox_fit,
                 cox_dose = cox_dose, cox_duration = cox_duration,
                 cox_release = cox_release))
}

results <- run_ot_analysis(df)
