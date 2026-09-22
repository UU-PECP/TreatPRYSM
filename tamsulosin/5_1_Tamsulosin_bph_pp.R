
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
library(MatchThem)
library(cobalt)
library(survey)
library(optmatch)

#read the datasets
df <- read.csv("F:\\Users\\Wyatt003\\Tamsulosin\\Output\\bph_perprotocol.csv", colClasses = c(patid = "character"))
sapply(df, class)

df %>% tabyl(exposure)
df %>% tabyl(exposure, aSAH)

#set datatypes
df$tamsulosin <- as.numeric(df$exposure==1) #make tamsulosin the explicit exposure
#sv df$tamsulosin <- ifelse(df$exposure > 1, 0, 1) #make tamsulosin the explicit exposure



#Calculate age at index_date
df <- df %>% 
  mutate(
    age_at_index = year(episode.start) - yob
  )

# Add NA smoking level

df$smk_status <- as.factor(replace_na(df$smk_status, 99))


#drop variables no longer needed
df <- df %>%
  select(-episode.ID, -end.episode.gap.days, -episode.duration, -episode.end, -yob,
         -aSAH_apc_dt, -censordate, -end_of_fu, -episode.start)


df %>% group_by(exposure) %>% count()
# table(df$exposure)

variable.names(df)
# names(df)


# descriptive table

vars_cat <- c("acidosis","aids","alcohol","alzheimers_disease",
              "cancer","chronic_liver","alopecia","copd","stroke","rheum_disease","diabetes","heart_failure",
              "hypercholesterolaemia","hypertension","nephrolith",
              "paralysis","peptic_ulcer","pvd","ckd","anticoagulants","antidiabetics","antiemetics",
              "antihypertensives","dutasteride","lipid_lowering", "nsaids","opioids",
              "snri","solifenacin","tadalafil","smk_status")
vars_num <- c("bmi_value", "age_at_index", "imd")

vars <- c(vars_cat,vars_num)

Table1 <- CreateTableOne(vars = vars, 
                         strata = "exposure", 
                         factorVars =vars_cat , 
                         data = df,
                         test = FALSE,
                         smd = TRUE)

print(Table1)
t1export <- print(Table1, printToggle = FALSE, smd = TRUE, quote = FALSE, noSpaces = TRUE)
t1export <- as.data.frame(t1export) %>% rownames_to_column(var = "Variable")
ft <- flextable(t1export) %>% bold(part = "header") %>% autofit()
save_as_docx(ft, path = "F:\\Users\\Wyatt003\\Tamsulosin\\Results\\tamsulosin_pp_table1.docx")

# ---------------------------------------------------------
# Incidence summary + Cox refit, parameterized by outcome/time column -
# reused for both the main analysis (fu_days/aSAH) and the sensitivity
# analysis (fu_days_specific/aSAH_specific) on the SAME weighted_list, so
# the expensive imputation + weighting + trimming only happens once.
# ---------------------------------------------------------
summarise_incidence <- function(weighted_list, time_col, event_col) {

  per_imp <- lapply(complete(weighted_list, "all"), function(x) {
    x %>%
      group_by(tamsulosin) %>%
      summarise(
        total_patients           = n_distinct(patid),
        total_cases              = sum(.data[[event_col]]),
        total_cases_weighted     = sum(.data[[event_col]] * weights),
        total_follow_up_weighted = sum(.data[[time_col]] * weights),
        total_fuy_weighted       = sum(.data[[time_col]] * weights) / 365.25,
        total_follow_up_years    = sum(.data[[time_col]]) / 365.25,
        .groups = "drop"
      ) %>%
      mutate(incidence_rate = (total_cases_weighted / total_fuy_weighted) * 1000)
  })

  # Average across imputations
  pooled <- bind_rows(per_imp, .id = "imputation") %>%
    group_by(tamsulosin) %>%
    summarise(
      total_patients         = mean(total_patients),
      total_cases            = mean(total_cases),          # unweighted case count
      total_cases_weighted   = mean(total_cases_weighted),  # weighted case count
      total_follow_up_years  = mean(total_follow_up_years),
      total_fuy_weighted     = mean(total_fuy_weighted),
      incidence_rate         = mean(incidence_rate),
      .groups = "drop"
    ) %>%
    # 95% CI on the weighted IR, SE from the weighted case count
    # (IR * exp(+-1.96/sqrt(weighted cases)))
    mutate(
      ir_lower = incidence_rate * exp(-1.96 / sqrt(total_cases_weighted)),
      ir_upper = incidence_rate * exp( 1.96 / sqrt(total_cases_weighted))
    )

  print(pooled)
  pooled
}

fit_weighted_cox <- function(weighted_list, time_col, event_col) {
  form <- as.formula(paste0("Surv(", time_col, ", ", event_col, ") ~ tamsulosin"))
  cox_fit <- with(weighted_list, svycoxph(form), cluster = TRUE)
  list(cox_fit = cox_fit, cox_pool = pool(cox_fit))
}

# ---------------------------------------------------------
# SMR Weighting setup
# ---------------------------------------------------------
run_smrw <- function(df) {

  pred_matrix <- make.predictorMatrix(df)
  pred_matrix[, !( dimnames(pred_matrix)[[2]]  %in%  c(vars_cat, "age_at_index") )] <- 0


  imputed <- mice(df, m = 3, method = 'pmm', seed = 123, predictorMatrix = pred_matrix)
  comp_list <- complete(imputed, "all")

  ps_formula <- tamsulosin ~ age_at_index + acidosis + aids + alzheimers_disease +
    cancer + copd + stroke + rheum_disease + diabetes + heart_failure +
    hypercholesterolaemia + hypertension + chronic_liver + alopecia + nephrolith + paralysis +
    peptic_ulcer + pvd + ckd + anticoagulants + antidiabetics + antiemetics +
    antihypertensives + dutasteride + lipid_lowering + nsaids + opioids + snri +
    solifenacin + tadalafil + bmi_value + smk_status + imd

  gc()

 weighted_list <- weightthem(ps_formula,
                            datasets    = imputed,
                            approach    = "within",
                            method      = "glm",
                            estimand    = "ATT"
  )

 weighted_list <- trim(weighted_list, at = 0.975)

  # ---- Main outcome: aSAH / fu_days ----
  summary_data <- summarise_incidence(weighted_list, "fu_days", "aSAH")
  cox_main <- fit_weighted_cox(weighted_list, "fu_days", "aSAH")

  # ---- Sensitivity outcome: aSAH_specific / fu_days_specific (excludes  ----
  # ---- non-specific I60.8/I60.9 codes) - reuses the SAME weighted_list, ----
  # ---- no re-imputation/re-weighting needed since PS weights only      ----
  # ---- depend on baseline covariates, not the outcome.                 ----
  summary_data_specific <- summarise_incidence(weighted_list, "fu_days_specific", "aSAH_specific")
  cox_specific <- fit_weighted_cox(weighted_list, "fu_days_specific", "aSAH_specific")

  list(
    weighted_list           = weighted_list,
    summary_data            = summary_data,
    cox_fit_crude           = cox_main$cox_fit,
    cox_pool_crude          = cox_main$cox_pool,
    summary_data_specific   = summary_data_specific,
    cox_fit_crude_specific  = cox_specific$cox_fit,
    cox_pool_crude_specific = cox_specific$cox_pool,
    imputed = imputed
  )
}

#---------------------------------------
#Running the functions
#---------------------------------------


alf_ref <- df[df$exposure %in% c(1,2), ]
fin_ref <- df[df$exposure %in% c(1,3), ]


alf_results_smrw <- run_smrw(alf_ref) 

fin_results_smrw <- run_smrw(fin_ref) 


#---------------------------------------
#Outputting results
#---------------------------------------

#Alfuzosin

tbl_regression(alf_results_smrw$cox_fit_crude, exponentiate = TRUE) %>% as_flex_table() %>% save_as_docx(path = "F:\\Users\\Wyatt003\\Tamsulosin\\Results\\alfuzosin_pp_cox_smrw.docx")
as.data.frame(alf_results_smrw$summary_data) %>%  writexl::write_xlsx(path = "F:\\Users\\Wyatt003\\Tamsulosin\\Results\\alfuzosin_pp_inc_smrw.xlsx")

# Sensitivity: aSAH redefined to exclude non-specific I60.8/I60.9
cat("\n--- Alfuzosin: aSAH_specific sensitivity HR ---\n")
print(summary(alf_results_smrw$cox_pool_crude_specific, exponentiate = TRUE))
tbl_regression(alf_results_smrw$cox_fit_crude_specific, exponentiate = TRUE) %>% as_flex_table() %>% save_as_docx(path = "F:\\Users\\Wyatt003\\Tamsulosin\\Results\\alfuzosin_pp_cox_smrw_specific.docx")
as.data.frame(alf_results_smrw$summary_data_specific) %>%  writexl::write_xlsx(path = "F:\\Users\\Wyatt003\\Tamsulosin\\Results\\alfuzosin_pp_inc_smrw_specific.xlsx")




#Finasteride


tbl_regression(fin_results_smrw$cox_fit_crude, exponentiate = TRUE) %>% as_flex_table() %>% save_as_docx(path = "F:\\Users\\Wyatt003\\Tamsulosin\\Results\\finasteride_pp_cox_smrw.docx")
as.data.frame(fin_results_smrw$summary_data) %>%  writexl::write_xlsx(path = "F:\\Users\\Wyatt003\\Tamsulosin\\Results\\finasteride_pp_inc_smrw.xlsx")

# Sensitivity: aSAH redefined to exclude non-specific I60.8/I60.9
cat("\n--- Finasteride: aSAH_specific sensitivity HR ---\n")
print(summary(fin_results_smrw$cox_pool_crude_specific, exponentiate = TRUE))
tbl_regression(fin_results_smrw$cox_fit_crude_specific, exponentiate = TRUE) %>% as_flex_table() %>% save_as_docx(path = "F:\\Users\\Wyatt003\\Tamsulosin\\Results\\finasteride_pp_cox_smrw_specific.docx")
as.data.frame(fin_results_smrw$summary_data_specific) %>%  writexl::write_xlsx(path = "F:\\Users\\Wyatt003\\Tamsulosin\\Results\\finasteride_pp_inc_smrw_specific.xlsx")



#---------------------------------------
#Plot incidence over time for both users.
#Kaplan-Meier stratified by exposure
#---------------------------------------


surv_fit <- survfit(Surv(fu_days, aSAH) ~ exposure,
                    data = df)

gg_crude <- ggsurvplot(
  surv_fit,
  fun = "event",
  conf.int = TRUE,
  censor = FALSE,
  break.time.by = 3650,
  xlab = "Follow-up (days)",
  ylab = "Cumulative incidence of aSAH",
  legend.labs = c("Tamsulosin", "Alfuzosin", "Finasteride"),
  palette = c("#d95f02", "#1b9e77", "#7570b3"),
  ggtheme = theme_minimal(base_size = 12),
  risk.table = TRUE,
  risk.table.height = 0.25,
  risk.table.y.text.col = TRUE,
  ylim = c(0, 0.02)
)


png("F:\\Users\\Wyatt003\\Tamsulosin\\Results\\tamsulosin_km_graph.png",
       height = 15,
       width = 20,
       unit = "cm",
       res = 300)
print(gg_crude)
dev.off()

#---------------------------------------
# Propensity score graph
#---------------------------------------

### Imputed data

  # Alfuzosin

pred_matrix <- make.predictorMatrix(alf_ref)
pred_matrix[, !( dimnames(pred_matrix)[[2]]  %in%  c(vars_cat, "age_at_index") )] <- 0
imputed <- mice(alf_ref, m = 5, method = 'pmm', seed = 123, predictorMatrix = pred_matrix)
d <- complete(imputed, 1)

ps_model <- glm(tamsulosin ~ age_at_index + acidosis + aids + alzheimers_disease +
                  cancer + copd + stroke + rheum_disease + diabetes + heart_failure +
                  hypercholesterolaemia + hypertension + chronic_liver + alopecia + nephrolith + paralysis +
                  peptic_ulcer + pvd + ckd + anticoagulants + antidiabetics + antiemetics +
                  antihypertensives + dutasteride + lipid_lowering + nsaids + opioids + snri +
                  solifenacin + tadalafil + bmi_value + smk_status + imd, data = d, family = "binomial")
d$pscore <- predict(ps_model, type = "response")

table(d$tamsulosin)
par(mfrow=c(2,1))
hist(d$pscore[d$tamsulosin==1],100, xlim = c(0.8, 1))
hist(d$pscore[d$tamsulosin==0],100, xlim = c(0.8, 1))

   # Finasteride

pred_matrix <- make.predictorMatrix(fin_ref)
pred_matrix[, !( dimnames(pred_matrix)[[2]]  %in%  c(vars_cat, "age_at_index") )] <- 0
imputed <- mice(fin_ref, m = 5, method = 'pmm', seed = 123, predictorMatrix = pred_matrix)
d <- complete(imputed, 1)

ps_model <- glm(tamsulosin ~ age_at_index + acidosis + aids + alzheimers_disease +
                  cancer + copd + stroke + rheum_disease + diabetes + heart_failure +
                  hypercholesterolaemia + hypertension + chronic_liver + alopecia + nephrolith + paralysis +
                  peptic_ulcer + pvd + ckd + anticoagulants + antidiabetics + antiemetics +
                  antihypertensives + dutasteride + lipid_lowering + nsaids + opioids + snri +
                  solifenacin + tadalafil + bmi_value + smk_status + imd, data = d, family = "binomial")
d$pscore <- predict(ps_model, type = "response")

table(d$tamsulosin)
par(mfrow=c(2,1))
hist(d$pscore[d$tamsulosin==1])
hist(d$pscore[d$tamsulosin==0])

   # Ps- distribution plot


output_ps_plot <- function(df, drug_results, label) { 
  

  pred_matrix <- make.predictorMatrix(df)
  pred_matrix[, !( dimnames(pred_matrix)[[2]]  %in%  c(vars_cat, "age_at_index") )] <- 0
  imputed <- mice(df, m = 5, method = 'pmm', seed = 123, predictorMatrix = pred_matrix)
  d <- complete(imputed, 1)

ps_model <- glm(tamsulosin ~ age_at_index + acidosis + aids + alzheimers_disease +
                  cancer + copd + stroke + rheum_disease + diabetes + heart_failure +
                  hypercholesterolaemia + hypertension + chronic_liver + alopecia + nephrolith + paralysis +
                  peptic_ulcer + pvd + ckd + anticoagulants + antidiabetics + antiemetics +
                  antihypertensives + dutasteride + lipid_lowering + nsaids + opioids + snri +
                  solifenacin + tadalafil + smk_status + imd, data = d, family = "binomial")
d$pscore <- predict(ps_model, type = "response")

imputed_plot <- ggplot(d, aes(x = pscore, fill = factor(tamsulosin))) +
  geom_density(alpha = 0.25, adjust = 2) +
  theme_minimal()+
  scale_fill_manual(values = c("0" = "blue", "1" = "red"), labels = c("Non-User", "User"))+
  ggtitle(paste0("Density plot for PS in unmatched ", label, " cohort"))

print(imputed_plot)

}

