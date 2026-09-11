
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
save_as_docx(ft, path = "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Export\\tamsulosin_pp_table1.docx")
# ---------------------------------------------------------
# 1.1 Matching with Replacement
# ---------------------------------------------------------
run_match_with_repl <- function(df) {
  
  pred_matrix <- make.predictorMatrix(df)
  pred_matrix[, !( dimnames(pred_matrix)[[2]]  %in%  c(vars_cat, "age_at_index") )] <- 0

  
  imputed <- mice(df, m = 5, method = 'pmm', seed = 123, predictorMatrix = pred_matrix)
  comp_list <- complete(imputed, "all")
  
  ps_formula <- tamsulosin ~ age_at_index + acidosis + aids + alzheimers_disease +
    cancer + copd + stroke + rheum_disease + diabetes + heart_failure +
    hypercholesterolaemia + hypertension + nephrolith + paralysis +
    peptic_ulcer + pvd + ckd + anticoagulants + antidiabetics + antiemetics +
    antihypertensives + dutasteride + lipid_lowering + nsaids + opioids + snri +
    solifenacin + tadalafil + bmi_value + smk_status
 
   matched_list <- matchthem(ps_formula,
                       datasets    = imputed,
                       approach    = "within",
                       method      = "nearest",
                       distance    = "glm",
                       link        = "logit",
                       replace     = TRUE,
                       caliper     = 0.2,
                       std.caliper = TRUE
  )
  
   matched_complete <- complete(matched_list, "all")
   matched_complete <- lapply(matched_complete,function(x)x[x$weights > 0,])

  
  # ---- Incidence rates, computed once off the first matched imputation ----
  summary_data <- lapply(matched_complete, function(x){
    x %>%
    group_by(tamsulosin) %>%
    summarise(
      total_cases          = sum(aSAH * weights),
      total_follow_up       = sum(fu_days * weights),
      total_follow_up_years = sum(fu_days * weights) / 365.25,
      .groups = "drop"
    ) %>%
    mutate(incidence_rate = (total_cases / total_follow_up_years) * 1000)
  })
  
  # ---- Cox model on each imputation, pooled ----
 cox_fits_crude <- lapply(matched_complete, function(d) {
   coxph(Surv(fu_days, aSAH) ~ tamsulosin, data = d, weights = weights, cluster = patid)
 })
 cox_fit_crude <- as.mira(cox_fits_crude)
 cox_pool_crude <- pool(cox_fit_crude)
  
  list(
    matched_list   = matched_list,
    matched_complete = matched_complete,
    summary_data   = summary_data,
    cox_fit_crude  = cox_fit_crude,
    cox_pool_crude = cox_pool_crude
  )
}

# ---------------------------------------------------------
# 1.2 Full Matching
# ---------------------------------------------------------
run_full_match <- function(df) {
  
  pred_matrix <- make.predictorMatrix(df)
  pred_matrix[, !( dimnames(pred_matrix)[[2]]  %in%  c(vars_cat, "age_at_index") )] <- 0

  
  imputed <- mice(df, m = 5, method = 'pmm', seed = 123, predictorMatrix = pred_matrix)
  comp_list <- complete(imputed, "all")
  
  ps_formula <- tamsulosin ~ age_at_index + acidosis + aids + alzheimers_disease +
    cancer + copd + stroke + rheum_disease + diabetes + heart_failure +
    hypercholesterolaemia + hypertension + nephrolith + paralysis +
    peptic_ulcer + pvd + ckd + anticoagulants + antidiabetics + antiemetics +
    antihypertensives + dutasteride + lipid_lowering + nsaids + opioids + snri +
    solifenacin + tadalafil + bmi_value + smk_status
  
  matched_list <- matchthem(ps_formula,
                            datasets    = imputed,
                            approach    = "within",
                            method      = "full",
                            distance    = "glm",
                            link        = "logit"
  )
  
  
  # ---- Incidence rates, computed once off the first matched imputation ----
  summary_data <- lapply(complete(matched_list, "all"), function(x){ 
    x %>%
      group_by(tamsulosin) %>%
      summarise(
        total_cases          = sum(aSAH * weights),
        total_follow_up       = sum(fu_days * weights),
        total_follow_up_years = sum(fu_days * weights) / 365.25,
        .groups = "drop"
      ) %>%
      mutate(incidence_rate = (total_cases / total_follow_up_years) * 1000)
  })
  
  # ---- Cox model on each imputation, pooled ----
    cox_fit_crude <- with(matched_list, 
      svycoxph(Surv(fu_days, aSAH) ~ tamsulosin), cluster = TRUE)
    

    cox_pool_crude <- pool(cox_fit_crude)
  
  list(
    matched_list   = matched_list,
    summary_data   = summary_data,
    cox_fit_crude  = cox_fit_crude,
    cox_pool_crude = cox_pool_crude,
    imputed = imputed
  )
}

# ---------------------------------------------------------
# 1.3 No matching
# ---------------------------------------------------------
run_no_match <- function(df) { 
  
  pred_matrix <- make.predictorMatrix(df)
  pred_matrix[, !( dimnames(pred_matrix)[[2]]  %in%  c(vars_cat, "age_at_index") )] <- 0

  
  imputed <- mice(df, m = 5, method = 'pmm', seed = 123, predictorMatrix = pred_matrix)
  comp_list <- complete(imputed, "all")
  
  # ---- Incidence rates, computed once off the first matched imputation ----
  summary_data <- lapply(comp_list, function(x){
    x %>%
      group_by(tamsulosin) %>%
      summarise(
        total_cases          = sum(aSAH),
        total_follow_up       = sum(fu_days),
        total_follow_up_years = sum(fu_days) / 365.25,
        .groups = "drop"
      ) %>%
      mutate(incidence_rate = (total_cases / total_follow_up_years) * 1000)
  })
  
  # ---- Cox model on each imputation, pooled ----
  cox_fits_crude <- lapply(comp_list, function(d) {
    coxph(Surv(fu_days, aSAH) ~ tamsulosin + hypertension + ckd + antihypertensives + lipid_lowering + smk_status + age_at_index, data = d)
  })
  cox_fit_crude <- as.mira(cox_fits_crude)
  cox_pool_crude <- pool(cox_fit_crude)
  
  list(
    summary_data   = summary_data,
    cox_fit_crude  = cox_fit_crude,
    cox_pool_crude = cox_pool_crude,
    imputed = imputed
  )
}


# ---------------------------------------------------------
# 1.4 SMR Weighting
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
  
  
  # ---- Incidence rates, computed once off the first weighted imputation ----
  summary_data <- lapply(complete(weighted_list, "all"), function(x){ 
    x %>%
      group_by(tamsulosin) %>%
      summarise(
        total_cases          = sum(aSAH * weights),
        total_follow_up       = sum(fu_days * weights),
        total_follow_up_years = sum(fu_days * weights) / 365.25,
        .groups = "drop"
      ) %>%
      mutate(incidence_rate = (total_cases / total_follow_up_years) * 1000)
  })
  
  # ---- Cox model on each imputation, pooled ----
  cox_fit_crude <- with(weighted_list, 
                         svycoxph(Surv(fu_days, aSAH) ~ tamsulosin), cluster = TRUE)
  
  
  cox_pool_crude <- pool(cox_fit_crude)
  
  list(
    weighted_list   = weighted_list,
    summary_data   = summary_data,
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


alf_results_repl <- run_match_with_repl(alf_ref) # the same control can be used for more cases
alf_results_full <- run_full_match(alf_ref[1:1000, ]) # all controls are forcibly matched to an exposed DO NOT RUN FULL DATA (it takes too long)
alf_results_none <- run_no_match(alf_ref) # matching not required due to narrow PS range
alf_results_smrw <- run_smrw(alf_ref) # smr weighting

fin_results_repl <- run_match_with_repl(fin_ref) # the same control can be used for more cases
fin_results_full <- run_full_match(fin_ref[1:1000, ]) # all controls are forcibly matched to an exposed DO NOT RUN FULL DATA (it takes too long)
fin_results_none <- run_no_match(fin_ref) # matching not required due to narrow PS range
fin_results_smrw <- run_smrw(fin_ref) # smr weighting

####

sapply(complete(alf_results_repl$matched_list, "all"), function(x) {
  c(total = nrow(x),
    matched = sum(x$weights >0),
    tam_total = sum(x$tamsulosin == 1),
    tam_matched = sum(x$tamsulosin == 1 & x$weights > 0))
}) ## there are only 3 unmatched tamsulosin patients

complete(alf_results_repl$matched_list, 1) %>% filter(tamsulosin == 0) %>% count(patid) %>% arrange(desc(n))
complete(alf_results_repl$matched_list, 1) %>% filter(tamsulosin == 0) %>% distinct(patid) %>% count()
complete(alf_results_repl$matched_list, 1) %>% filter(tamsulosin == 0) %>% count()
complete(alf_results_repl$matched_list, 1) %>% count(tamsulosin)
## Each control still seems to be only used once, even with replacement

sapply(complete(alf_results_full$matched_list, "all"), function(x) {
  c(total = nrow(x),
    matched = sum(x$weights >0),
    tam_total = sum(x$tamsulosin == 1),
    tam_matched = sum(x$tamsulosin == 1 & x$weights > 0))
}) ## there is only 1 unmatched tamsulosin patient

print(alf_results_none$summary_data)

summary(complete(alf_results_smrw$weighted_list, 1)$weights)

#---------------------------------------
#Outputting results
#---------------------------------------

#Alfuzosin

tbl_regression(alf_results_repl$cox_fit_crude, exponentiate = TRUE) %>% as_flex_table() %>% save_as_docx(path = "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Export\\alfuzosin_pp_cox_repl.docx")
tbl_regression(alf_results_none$cox_fit_crude, exponentiate = TRUE) %>% as_flex_table() %>% save_as_docx(path = "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Export\\alfuzosin_pp_cox_none.docx")
tbl_regression(alf_results_smrw$cox_fit_crude, exponentiate = TRUE) %>% as_flex_table() %>% save_as_docx(path = "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Export\\alfuzosin_pp_cox_smrw.docx")

summary(alf_results_repl$cox_fit_crude, conf.int = TRUE, exponentiate = TRUE)
summary(alf_results_none$cox_fit_crude, conf.int = TRUE, exponentiate = TRUE)
summary(alf_results_smrw$cox_fit_crude, conf.int = TRUE, exponentiate = TRUE)

as.data.frame(alf_results_repl$summary_data) %>%  writexl::write_xlsx(path = "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Export\\alfuzosin_pp_inc_repl.xlsx")
as.data.frame(alf_results_none$summary_data) %>%  writexl::write_xlsx(path = "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Export\\alfuzosin_pp_inc_none.xlsx")
as.data.frame(alf_results_smrw$summary_data) %>%  writexl::write_xlsx(path = "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Export\\alfuzosin_pp_inc_smrw.xlsx")




#Finasteride

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
  ylim = c(0, 0.05)
)


png("C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Export\\tamsulosin_km_graph.png",
       height = 15,
       width = 20,
       unit = "cm",
       res = 300)
print(gg_crude)
dev.off()

#---------------------------------------
#Matched Table One's, drug specific Table One's and Balance Tables
#---------------------------------------


### for alfuzosin

  # Drug-specific

MatchedTable1 <- CreateTableOne(vars = vars, 
                                strata = "exposure", 
                                factorVars = vars_cat, data = alf_ref)
  

print(MatchedTable1)
mt1export <- print(MatchedTable1, printToggle = FALSE, test = FALSE, smd = TRUE, quote = FALSE, noSpaces = TRUE)
mt1export <- as.data.frame(mt1export) %>% rownames_to_column(var = "Variable")
ft <- flextable(mt1export) %>% bold(part = "header") %>% autofit() %>% set_header_labels(`1` = "Tamsulosin", `2` = "ALfuzosin")
save_as_docx(ft, path = "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Export\\alfuzosin_pp_table1.docx")

  # Matched

matched_df <- complete(alf_results_repl$matched_list, 1)

MatchedTable1 <- CreateTableOne(vars = vars, 
                         strata = "exposure", 
                         factorVars = vars_cat, data = matched_df)

print(MatchedTable1)
mt1export <- print(MatchedTable1, printToggle = FALSE, test = FALSE, smd = TRUE, quote = FALSE, noSpaces = TRUE)
mt1export <- as.data.frame(mt1export) %>% rownames_to_column(var = "Variable")
ft <- flextable(mt1export) %>% bold(part = "header") %>% autofit() %>% set_header_labels(`1` = "Tamsulosin", `2` = "ALfuzosin")
save_as_docx(ft, path = "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Export\\alfuzosin_pp_matched_table1.docx")


### for finasteride

  # Drug-specific

MatchedTable1 <- CreateTableOne(vars = vars, 
                                strata = "exposure", 
                                factorVars = vars_cat, data = fin_ref)


print(MatchedTable1)
mt1export <- print(MatchedTable1, printToggle = FALSE, test = FALSE, smd = TRUE, quote = FALSE, noSpaces = TRUE)
mt1export <- as.data.frame(mt1export) %>% rownames_to_column(var = "Variable")
ft <- flextable(mt1export) %>% bold(part = "header") %>% autofit() %>% set_header_labels(`1` = "Tamsulosin", `3` = "Finasteride")
save_as_docx(ft, path = "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Export\\finasteride_pp_table1.docx")

  # Matched

matched_df <- complete(fin_results_repl$matched_list, 1)

MatchedTable1 <- CreateTableOne(vars = vars, 
                                strata = "exposure", 
                                factorVars = vars_cat, data = matched_df)



print(MatchedTable1)
mt1export <- print(MatchedTable1, printToggle = FALSE, test = FALSE, smd = TRUE, quote = FALSE, noSpaces = TRUE)
mt1export <- as.data.frame(mt1export) %>% rownames_to_column(var = "Variable")
ft <- flextable(mt1export) %>% bold(part = "header") %>% autofit()%>% set_header_labels(`1` = "Tamsulosin", `3` = "Finasteride")
save_as_docx(ft, path = "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Export\\finasteride_pp_matched_table1.docx")


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
hist(d$pscore[d$tamsulosin==1],100, xlim = c(0.8, 1))
hist(d$pscore[d$tamsulosin==0],100, xlim = c(0.8, 1))

   # Colorful plot


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

### Matched data

matched_plot <- ggplot(complete(drug_results$matched_list, 1), aes(x = distance, fill = factor(tamsulosin))) +
  geom_density(alpha = 0.25, adjust = 2) +
  labs(x = "Propensity score", y = "Density", fill = "Tamsulosin user") +
  theme_minimal()+
  scale_fill_manual(values = c("0" = "blue", "1" = "red"), labels = c("Non-User", "User"))+
  ggtitle(paste0("Density plot for PS in matched ", label, " cohort"))

ggsave(file.path("C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Export", paste0("density_ps_imputed_", label, ".png")),
       plot = imputed_plot,
       dpi = 300)

ggsave(file.path("C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Export", paste0("density_ps_matched_", label, ".png")),
       plot = matched_plot,
       dpi = 300)

}


output_ps_plot(df = alf_ref, drug_results = alf_results_repl, label = "alfuzosin")
output_ps_plot(df = fin_ref, drug_results = fin_results_repl, label = "finasteride")
