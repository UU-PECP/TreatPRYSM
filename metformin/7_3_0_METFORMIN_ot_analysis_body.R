## the Treat-PRYSM project
## Drug - Metformin
##
## File 7_3_0: On-treatment analysis - SHARED BODY
## Re-adapted from tamsulosin/7_3_tamsulosin_ot.R's current design, per an
## explicit decision to structurally match it rather than keep the earlier
## single combined 4-level recency factor.
##
## WHAT CHANGED FROM THE EARLIER VERSION OF THIS FILE:
##
## 1) recency is now crossed with the drug flag into a 6-level factor
##    (Current/Recent/Past x Comparator/metformin, reference =
##    "Current_0" i.e. current comparator use) instead of the earlier
##    4-level one (Comparator / Index-Current / Index-Recent /
##    Index-Past). This needs 7_0's treatment_recency_status to be
##    computed per episode-row for whichever drug that row is for -
##    including comparator episodes - not just the index drug, which is
##    why 7_0's BridgeCoverage table changed too (see its header).
## 2) the recency model (cox_fit_rec, drug x recency only) and the
##    adjusted model (cox_fit_adj, drug indicator + confounders, no
##    recency) are now two SEPARATE models, matching tamsulosin's current
##    "crude / adjusted / recency / dose" 4-way split, rather than one
##    model with both terms combined additively.
## 3) output moved from sink()-ed plain text to gtsummary::tbl_regression
##    + flextable + save_as_docx (matching tamsulosin/7_3 and metformin's
##    own per-protocol scripts, 5_0/5_1/5_2), and incidence to xlsx via
##    writexl instead of a sink()-ed text dump.
##
## The duration and release-pattern sensitivity models are METFORMIN-ONLY
## additions with no tamsulosin equivalent - kept as-is (just reformatted
## to docx), since there was nothing to adapt them FROM.
##
## Two known limitations inherited from 7_0, NOT fixed here (see that
## file's header for detail - both were left as a deliberate decision
## while porting tamsulosin's design, not introduced by this file):
## dose_category's underlying mean_daily_dose is a per-tablet-strength
## average, not a true per-day dose; and mg_value_current/
## release_pattern_current can pick up the comparator's own values
## mid-episode since they aren't filtered to the patient's own drug.
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
library(gtsummary)
library(flextable)
library(writexl)

df <- read_sas(ot_sas_path)
sapply(df, class)

setwd(results_dir)

## Exposure coding: 1 = metformin, 2 = comparator
df$metformin <- ifelse(df$index_exposure == 1, 1, 0)

## NOTE: fu_days already comes in from SAS (7_0, Step: end_of_fu - index_date + 1)
## as a per-episode follow-up duration - do not overwrite it here with a
## per-interval quantity.
df <- df %>%
  filter(interval_window_start > lubridate::ymd(study_start_date)) %>%
  filter(interval_window_start < end_of_fu)

###############################
# RUN OT ANALYSIS #
###############################

run_ot_analysis <- function(df) {

  d <- df

  ## ---- patient-level collapse for crude incidence / KM ----
  ## d has one row per 30-day interval per EPISODE (a patient can have
  ## more than one episode of either drug in play). index_date/metformin/
  ## end_of_fu/fu_days are episode-level, not patient-level, so they can't
  ## be collapsed with independent min()s across a patient's episodes
  ## without risking pairing one episode's index_date with a DIFFERENT
  ## episode's fu_days/metformin flag. Instead: take metformin/index_date/
  ## end_of_fu/fu_days together from the patient's earliest episode, and
  ## compute aSAH separately as "ever, across any of their episodes".
  aSAH_ever <- d %>%
    group_by(patid) %>%
    summarise(aSAH = max(aSAH_within_interval), .groups = "drop")

  first_episode <- d %>%
    group_by(patid) %>%
    slice_min(index_date, n = 1, with_ties = FALSE) %>%
    ungroup() %>%
    select(patid, metformin, index_date, end_of_fu, fu_days)

  individual_data <- first_episode %>%
    left_join(aSAH_ever, by = "patid")

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
  as.data.frame(summary_data) %>%
    writexl::write_xlsx(path = paste0("metformin_", cohort_label, "_ot_incidence.xlsx"))

  ## ---- crude Cox (patient level) ----
  cox_model <- coxph(Surv(time = fu_days, event = aSAH) ~ metformin,
                     data = individual_data)
  tbl_regression(cox_model, exponentiate = TRUE) %>%
    as_flex_table() %>%
    save_as_docx(path = paste0("metformin_", cohort_label, "_ot_cox.docx"))

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
  ##  Fill missing BMI by per-patient median (keep NA if all missing),
  ##  and an ever-aSAH flag, for the time-varying confounder plot and
  ##  the counting-process Cox models below.
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

  ## ============================================================
  ##  Time-varying confounder plot: BMI over time
  ## ============================================================
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
  ##  Counting-process Cox: recency model
  ##  6-level factor crossing recency with drug (Current_0/Past_0/
  ##  Recent_0/Current_1/Past_1/Recent_1, "_0" = comparator episode,
  ##  "_1" = metformin episode), reference = "Current_0" (current
  ##  comparator use) - matches tamsulosin/7_3's current design exactly.
  ## ============================================================
  d_filled <- d_filled %>% mutate(recency = paste0(treatment_recency_status, "_", metformin))

  keep <- c("patid",
            "interval_window_start", "interval_window_end", "index_date",
            "aSAH_within_interval",
            "recency",
            "metformin", "dose_category", "duration_category",
            "release_pattern_current",
            "bmi_value", "smk_cur", "smk_ex", "smk_non",
            "gender", "age_at_interval_start")

  d_cox_src <- d_filled[, keep]
  setDT(d_cox_src)

  df_cox <- copy(d_cox_src)[ , `:=`(
    tstart  = as.numeric(interval_window_start - index_date),
    tstop   = as.numeric(interval_window_end   - index_date),
    rec_fac = factor(recency,
                     levels = c("Current_0", "Past_0", "Recent_0", "Current_1", "Past_1", "Recent_1"))
  )][ , c("interval_window_start", "interval_window_end",
          "index_date", "recency") := NULL ]

  setorder(df_cox, tstop)

  cox_fit_rec <- coxph(
    Surv(tstart, tstop, aSAH_within_interval) ~
      relevel(rec_fac, ref = "Current_0") +
      gender + bmi_value + smk_cur + smk_ex +        # smk_non is the reference smoking level
      age_at_interval_start,
    data    = df_cox,
    cluster = patid,
    ties    = "breslow",
    x = FALSE, y = FALSE, model = FALSE,
    robust  = TRUE,
    control = coxph.control(timefix = FALSE, iter.max = 20)
  )

  ## ============================================================
  ##  Counting-process Cox: adjusted model (drug indicator only, no
  ##  recency - a distinct output from the recency model above, matching
  ##  tamsulosin/7_3's current design).
  ## ============================================================
  cox_fit_adj <- coxph(
    Surv(tstart, tstop, aSAH_within_interval) ~
      metformin +
      gender + bmi_value + smk_cur + smk_ex +
      age_at_interval_start,
    data    = df_cox,
    cluster = patid,
    ties    = "breslow",
    x = FALSE, y = FALSE, model = FALSE,
    robust  = TRUE,
    control = coxph.control(timefix = FALSE, iter.max = 20)
  )

  tbl_regression(cox_fit_rec, exponentiate = TRUE) %>% as_flex_table() %>%
    save_as_docx(path = paste0("metformin_", cohort_label, "_ot_recency.docx"))
  tbl_regression(cox_fit_adj, exponentiate = TRUE) %>% as_flex_table() %>%
    save_as_docx(path = paste0("metformin_", cohort_label, "_ot_adjusted.docx"))

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
  tbl_regression(cox_dose, exponentiate = TRUE) %>% as_flex_table() %>%
    save_as_docx(path = paste0("metformin_", cohort_label, "_ot_dose.docx"))

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
  tbl_regression(cox_duration, exponentiate = TRUE) %>% as_flex_table() %>%
    save_as_docx(path = paste0("metformin_", cohort_label, "_ot_duration.docx"))

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
  tbl_regression(cox_release, exponentiate = TRUE) %>% as_flex_table() %>%
    save_as_docx(path = paste0("metformin_", cohort_label, "_ot_release.docx"))

  invisible(list(incidence = summary_data, cox_crude = cox_model,
                 cox_recency = cox_fit_rec, cox_adjusted = cox_fit_adj,
                 cox_dose = cox_dose, cox_duration = cox_duration,
                 cox_release = cox_release))
}

results <- run_ot_analysis(df)
gc()
