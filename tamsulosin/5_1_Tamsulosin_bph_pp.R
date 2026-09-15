
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
              "cancer","copd","stroke","rheum_disease","diabetes","heart_failure",        
              "hypercholesterolaemia","hypertension","cirrhosis","nephrolith",          
              "paralysis","peptic_ulcer","pvd","ckd","anticoagulants","antidiabetics","antiemetics",        
              "antihypertensives","dutasteride","lipid_lowering", "nsaids","opioids",                      
              "snri","solifenacin","tadalafil","smk_status")
vars_num <- c("bmi_value", "age_at_index")

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
# SMR Weighting setup
# ---------------------------------------------------------
run_smrw <- function(df) { 
  
  pred_matrix <- make.predictorMatrix(df)
  pred_matrix[, !( dimnames(pred_matrix)[[2]]  %in%  c(vars_cat, "age_at_index") )] <- 0
  
  
  imputed <- mice(df, m = 3, method = 'pmm', seed = 123, predictorMatrix = pred_matrix)
  comp_list <- complete(imputed, "all")
  
  ps_formula <- tamsulosin ~ age_at_index + acidosis + aids + alzheimers_disease +
    cancer + copd + stroke + rheum_disease + diabetes + heart_failure +
    hypercholesterolaemia + hypertension + nephrolith + paralysis +
    peptic_ulcer + pvd + ckd + anticoagulants + antidiabetics + antiemetics +
    antihypertensives + dutasteride + lipid_lowering + nsaids + opioids + snri +
    solifenacin + tadalafil + bmi_value + smk_status
  
  gc()
  
 weighted_list <- weightthem(ps_formula,
                            datasets    = imputed,
                            approach    = "within",
                            method      = "glm",
                            estimand    = "ATT"
  )
  
 weighted_list <- trim(weighted_list, at = 0.975)
  
  # ---- Incidence rates, computed once off the first weighted imputation ----
  summary_data <- lapply(complete(weighted_list, "all"), function(x){ 
    x %>%
      group_by(tamsulosin) %>%
      summarise(
        total_patients       = n_distinct(patid),
        total_cases          = sum(aSAH * weights),
        total_follow_up       = sum(fu_days * weights),
        total_follow_up_years = sum(fu_days * weights) / 365.25,
        .groups = "drop"
      ) %>%
      mutate(incidence_rate = (total_cases / total_follow_up_years) * 1000)
  })
 
 # Average across the 5 imputations
 summary_data_pooled <- bind_rows(summary_data, .id = "imputation") %>%
   group_by(tamsulosin) %>%
   summarise(
     total_patients        = mean(total_patients),
     total_cases           = mean(total_cases),
     total_follow_up_years = mean(total_follow_up_years),
     mean_fu_days          = mean(total_follow_up),
     mean_fu_years         = mean(total_follow_up_years),
     incidence_rate        = mean(incidence_rate),
     .groups = "drop"
   )
  
  # ---- Cox model on each imputation, pooled ----
  cox_fit_crude <- with(weighted_list, 
                         svycoxph(Surv(fu_days, aSAH) ~ tamsulosin), cluster = TRUE)
  
  
  cox_pool_crude <- pool(cox_fit_crude)
  
  list(
    weighted_list   = weighted_list,
    summary_data   = summary_data_pooled,
    cox_fit_crude  = cox_fit_crude,
    cox_pool_crude = cox_pool_crude,
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




#Finasteride


tbl_regression(fin_results_smrw$cox_fit_crude, exponentiate = TRUE) %>% as_flex_table() %>% save_as_docx(path = "F:\\Users\\Wyatt003\\Tamsulosin\\Results\\finasteride_pp_cox_smrw.docx")
as.data.frame(fin_results_smrw$summary_data) %>%  writexl::write_xlsx(path = "F:\\Users\\Wyatt003\\Tamsulosin\\Results\\finasteride_pp_inc_smrw.xlsx")



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
                  hypercholesterolaemia + hypertension + nephrolith + paralysis +
                  peptic_ulcer + pvd + ckd + anticoagulants + antidiabetics + antiemetics +
                  antihypertensives + dutasteride + lipid_lowering + nsaids + opioids + snri +
                  solifenacin + tadalafil + bmi_value + smk_status, data = d, family = "binomial")
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
                  hypercholesterolaemia + hypertension + nephrolith + paralysis +
                  peptic_ulcer + pvd + ckd + anticoagulants + antidiabetics + antiemetics +
                  antihypertensives + dutasteride + lipid_lowering + nsaids + opioids + snri +
                  solifenacin + tadalafil + bmi_value + smk_status, data = d, family = "binomial")
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
                  hypercholesterolaemia + hypertension + cirrhosis + nephrolith + paralysis +
                  peptic_ulcer + pvd + ckd + anticoagulants + antidiabetics + antiemetics +
                  antihypertensives + dutasteride + lipid_lowering + nsaids + opioids + snri +
                  solifenacin + tadalafil + smk_status, data = d, family = "binomial")
d$pscore <- predict(ps_model, type = "response")

imputed_plot <- ggplot(d, aes(x = pscore, fill = factor(tamsulosin))) +
  geom_density(alpha = 0.25, adjust = 2) +
  theme_minimal()+
  scale_fill_manual(values = c("0" = "blue", "1" = "red"), labels = c("Non-User", "User"))+
  ggtitle(paste0("Density plot for PS in unmatched ", label, " cohort"))

print(imputed_plot)

}

