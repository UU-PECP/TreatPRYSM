## the Treat-PRYSM project
## Drug - Metformin
##
## File 5_0: Per-protocol analysis - SHARED BODY
## Modelled on tamsulosin/5_1_Tamsulosin_bph_pp.R, simplified to ONE
## comparator per cohort (tamsulosin's BPH analysis has two comparators,
## alfuzosin and finasteride, compared in parallel blocks within one
## script - metformin's two cohorts each have exactly one comparator,
## so that duplication doesn't apply here).
##
## Deviations from the tamsulosin script, per protocol:
##   - PS trimming: drop propensity scores below the 2.5th or above the
##     97.5th percentile before matching (asymmetric trimming) - not in
##     the tamsulosin script, added here.
##   - Matching caliper 0.02 (metformin protocol), not 0.2 (tamsulosin's
##     amended value).
##   - "sex" (gender) included as a PS/adjustment covariate - the BPH
##     cohort is male-only so tamsulosin's script never includes it.
##   - Matching WITHOUT replacement, 1:1 nearest-neighbour - the
##     protocol only specifies "nearest neighbour matching", not
##     replacement; tamsulosin's amendment specifically opted into
##     matching with replacement, which isn't stated for metformin, so
##     this uses MatchIt's more common 1:1-without-replacement default.
##     Revisit if that's not actually what's intended.
##
## source() this from a per-cohort driver (5_1/5_2) that has already
## set the variables below. Do not run this file directly.
##
## Required variables from the driver:
##   cohort_label       - e.g. "su" / "sglt2i"
##   comparator_name     - e.g. "sulphonylureas" / "SGLT2 inhibitors" (for labels/filenames)
##   perprotocol_csv_path - path to the <cohort>_perprotocol.csv from 4_0
##   table1_docx_path     - output path for the unmatched Table 1
##   matched_table1_docx_path - output path for the matched Table 1
##   cox_docx_path         - output path for the Cox model table
##   km_png_path            - output path for the KM plot

library(tidyverse)
library(haven)
library(lubridate)
library(MatchIt)
library(mice)
library(dplyr)
library(ggplot2)
library(scales)
library(survival)
library(survminer)
library(tableone)
library(janitor)
library(gtsummary)
library(flextable)
library(cobalt)

## NOTE: tamsulosin/5_1 uses MatchThem (matchthem()) to run PS matching
## across all multiply-imputed datasets in one call. That doesn't have a
## clean way to insert a trimming step between "fit the PS model" and
## "match" for each imputation, so this uses mice() for imputation, then
## a manual per-imputation loop of glm() -> trim to the 2.5th/97.5th PS
## percentile -> matchit(), pooling the resulting Cox model fits by hand
## with mice::pool(). Functionally equivalent to the tamsulosin approach
## otherwise, just with trimming spliced in.

df <- read.csv(perprotocol_csv_path, colClasses = c(patid = "character"))

df %>% tabyl(exposure)
df %>% tabyl(exposure, aSAH)

df$metformin <- as.numeric(df$exposure == 1)  ## make metformin the explicit exposure

## Calculate age at index_date
df <- df %>%
  mutate(
    age_at_index = year(episode.start) - yob
  )

## Add NA smoking level
df$smk_status <- as.factor(replace_na(df$smk_status, 99))

## Sex as a factor (both sexes present, unlike the tamsulosin BPH cohort)
df$gender <- as.factor(df$gender)

## drop variables no longer needed
df <- df %>%
  select(-episode.ID, -end.episode.gap.days, -episode.duration, -episode.end, -yob,
         -aSAH_apc_dt, -censordate, -end_of_fu, -episode.start)

df %>% group_by(exposure) %>% count()

variable.names(df)

## descriptive table

vars_cat <- c("acidosis", "aids", "alcohol", "alzheimers_disease",
              "cancer", "copd", "stroke", "rheum_disease", "heart_failure",
              "hypercholesterolaemia", "hypertension", "chronic_liver",
              "paralysis", "peptic_ulcer", "pvd", "ckd", "anticoagulants", "antiemetics",
              "antihypertensives", "lipid_lowering", "nsaids", "opioids",
              "snri", "smk_status", "gender")
vars_num <- c("bmi_value", "age_at_index")

vars <- c(vars_cat, vars_num)

Table1 <- CreateTableOne(vars = vars,
                         strata = "exposure",
                         factorVars = vars_cat,
                         data = df,
                         test = FALSE,
                         smd = TRUE)

print(Table1)
t1export <- print(Table1, printToggle = FALSE, smd = TRUE, quote = FALSE, noSpaces = TRUE)
t1export <- as.data.frame(t1export) %>% rownames_to_column(var = "Variable")
ft <- flextable(t1export) %>% bold(part = "header") %>% autofit()
save_as_docx(ft, path = table1_docx_path)

# ---------------------------------------------------------
# Incidence summary + Cox refit, parameterized by outcome/time column -
# reused for both the main analysis (fu_days/aSAH) and the sensitivity
# analysis (fu_days_specific/aSAH_specific) on the SAME matched_complete
# list, since matching only uses baseline covariates (never the outcome),
# so there's no need to re-impute/re-trim/re-match for the sensitivity
# analysis.
# ---------------------------------------------------------
summarise_incidence_matched <- function(matched_complete, time_col, event_col) {

  per_imp <- lapply(matched_complete, function(x) {
    x %>%
      group_by(metformin) %>%
      summarise(
        total_patients        = n_distinct(patid),
        total_cases           = sum(.data[[event_col]]),
        total_cases_weighted  = sum(.data[[event_col]] * weights),
        total_follow_up_years = sum(.data[[time_col]]) / 365.25,
        total_fuy_weighted    = sum(.data[[time_col]] * weights) / 365.25,
        .groups = "drop"
      ) %>%
      mutate(incidence_rate = (total_cases_weighted / total_fuy_weighted) * 1000)
  })

  # Average across imputations
  pooled <- bind_rows(per_imp, .id = "imputation") %>%
    group_by(metformin) %>%
    summarise(
      total_patients         = mean(total_patients),
      total_cases            = mean(total_cases),          # unweighted case count
      total_cases_weighted   = mean(total_cases_weighted),  # weighted (match-weight) case count
      total_follow_up_years  = mean(total_follow_up_years),
      total_fuy_weighted     = mean(total_fuy_weighted),
      incidence_rate         = mean(incidence_rate),
      .groups = "drop"
    ) %>%
    # 95% CI on the weighted IR, SE from the weighted case count
    mutate(
      ir_lower = incidence_rate * exp(-1.96 / sqrt(total_cases_weighted)),
      ir_upper = incidence_rate * exp( 1.96 / sqrt(total_cases_weighted))
    )

  print(pooled)
  pooled
}

fit_matched_cox <- function(matched_complete, time_col, event_col) {
  form <- as.formula(paste0("Surv(", time_col, ", ", event_col, ") ~ metformin"))
  cox_fits <- lapply(matched_complete, function(d) {
    coxph(form, data = d, weights = weights, cluster = patid)
  })
  cox_fit <- as.mira(cox_fits)
  list(cox_fit = cox_fit, cox_pool = pool(cox_fit))
}

# ---------------------------------------------------------
# PS trimming (asymmetric, 2.5th/97.5th percentile) then
# 1:1 nearest-neighbour matching without replacement
# ---------------------------------------------------------
run_match <- function(df) {

  pred_matrix <- make.predictorMatrix(df)
  pred_matrix[, !(dimnames(pred_matrix)[[2]] %in% c(vars_cat, "age_at_index"))] <- 0

  imputed <- mice(df, m = 5, method = 'pmm', seed = 123, predictorMatrix = pred_matrix)

  ps_formula <- metformin ~ age_at_index + gender + acidosis + aids + alzheimers_disease +
    cancer + copd + stroke + rheum_disease + heart_failure +
    hypercholesterolaemia + hypertension + chronic_liver + paralysis +
    peptic_ulcer + pvd + ckd + anticoagulants + antiemetics +
    antihypertensives + lipid_lowering + nsaids + opioids + snri +
    bmi_value + smk_status

  ## Fit the PS model on each imputation, trim to the 2.5th-97.5th
  ## percentile range of the PS distribution, then match within that
  ## trimmed set.
  comp_list <- complete(imputed, "all")

  trimmed_list <- lapply(comp_list, function(d) {
    ps_model <- glm(ps_formula, data = d, family = binomial())
    d$pscore <- predict(ps_model, type = "response")
    lo <- quantile(d$pscore, 0.025)
    hi <- quantile(d$pscore, 0.975)
    d[d$pscore >= lo & d$pscore <= hi, ]
  })

  matched_list <- lapply(trimmed_list, function(d) {
    matchit(ps_formula,
            data     = d,
            method   = "nearest",
            distance = "glm",
            link     = "logit",
            replace  = FALSE,
            caliper  = 0.02,
            std.caliper = TRUE)
  })

  matched_complete <- lapply(seq_along(matched_list), function(i) {
    match.data(matched_list[[i]])
  })

  # ---- Main outcome: aSAH / fu_days ----
  summary_data <- summarise_incidence_matched(matched_complete, "fu_days", "aSAH")
  cox_main <- fit_matched_cox(matched_complete, "fu_days", "aSAH")

  # ---- Sensitivity outcome: aSAH_specific / fu_days_specific (excludes  ----
  # ---- non-specific I60.8/I60.9 codes) - reuses the SAME matched_complete
  # ---- list, no re-imputation/re-trimming/re-matching needed since
  # ---- matching only ever used baseline covariates, never the outcome.
  summary_data_specific <- summarise_incidence_matched(matched_complete, "fu_days_specific", "aSAH_specific")
  cox_specific <- fit_matched_cox(matched_complete, "fu_days_specific", "aSAH_specific")

  cox_fits_adj <- lapply(matched_complete, function(d) {
    coxph(Surv(fu_days, aSAH) ~ metformin + gender + hypertension + ckd +
            antihypertensives + lipid_lowering + smk_status + age_at_index,
          data = d, weights = weights, cluster = patid)
  })
  cox_fit_adj <- as.mira(cox_fits_adj)
  cox_pool_adj <- pool(cox_fit_adj)

  list(
    imputed                 = imputed,
    matched_list            = matched_list,
    matched_complete        = matched_complete,
    summary_data            = summary_data,
    cox_fit_crude           = cox_main$cox_fit,
    cox_pool_crude          = cox_main$cox_pool,
    summary_data_specific   = summary_data_specific,
    cox_fit_crude_specific  = cox_specific$cox_fit,
    cox_pool_crude_specific = cox_specific$cox_pool,
    cox_fit_adj             = cox_fit_adj,
    cox_pool_adj            = cox_pool_adj
  )
}

results <- run_match(df)

## ---- Reporting ----

summary(results$cox_pool_crude, conf.int = TRUE, exponentiate = TRUE)
summary(results$cox_pool_adj, conf.int = TRUE, exponentiate = TRUE)

tbl_regression(results$cox_fit_crude, exponentiate = TRUE) %>%
  as_flex_table() %>%
  save_as_docx(path = cox_docx_path)

## Sensitivity: aSAH redefined to exclude non-specific I60.8/I60.9
cat("\n--- aSAH_specific sensitivity HR ---\n")
print(summary(results$cox_pool_crude_specific, conf.int = TRUE, exponentiate = TRUE))
tbl_regression(results$cox_fit_crude_specific, exponentiate = TRUE) %>%
  as_flex_table() %>%
  save_as_docx(path = sub("\\.docx$", "_specific.docx", cox_docx_path))

## Matched Table 1
mt1export <- results$matched_complete[[1]] %>%
  CreateTableOne(vars = vars, strata = "metformin", factorVars = vars_cat, data = ., test = FALSE, smd = TRUE) %>%
  print(printToggle = FALSE, smd = TRUE, quote = FALSE, noSpaces = TRUE) %>%
  as.data.frame() %>%
  rownames_to_column(var = "Variable")

ft_matched <- flextable(mt1export) %>% bold(part = "header") %>% autofit() %>%
  set_header_labels(`0` = "Comparator", `1` = "Metformin")
save_as_docx(ft_matched, path = matched_table1_docx_path)

## Kaplan-Meier plot (first imputation/matched set)
km_fit <- survfit(Surv(fu_days, aSAH) ~ metformin, data = results$matched_complete[[1]])

png(km_png_path, width = 1200, height = 900, res = 150)
print(ggsurvplot(km_fit,
           data = results$matched_complete[[1]],
           legend.labs = c(comparator_name, "Metformin"),
           risk.table = TRUE))
dev.off()
