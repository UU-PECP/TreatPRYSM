
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

#read the datasets
df <- read.csv("F:\\Users\\Wyatt003\\BPH_nephrolithiasis\\Output\\bph_perprotocol.csv", colClasses = c(patid = "character"))
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
  select(-patid, -episode.ID, -end.episode.gap.days, -episode.duration, -episode.end, -yob,
         -aSAH_gp_dt, -baseline_dt, -censordate, -end_of_fu, -episode.start)


df %>% group_by(exposure) %>% count()
# table(df$exposure)

variable.names(df)
# names(df)


# descriptive table

# var <- c("acidosis","aids","alcohol","alzheimers_disease",
#               "cancer","copd","stroke","rheum_disease","diabetes","heart_failure",        
#               "hypercholesterolaemia","hypertension","liver_failure","nephrolith",          
#               "paralysis","peptic_ulcer","pvd","ckd","anticoagulants","antidiabetics","antiemetics",        
#               "antihypertensives","dutasteride","lipid_lowering", "nsaids","opioids",                      
#               "snri","solifenacin","tadalafil","smk_status","bmi_value", "age_at_index")
vars_cat <- c("acidosis","aids","alcohol","alzheimers_disease",
              "cancer","copd","stroke","rheum_disease","diabetes","heart_failure",        
              "hypercholesterolaemia","hypertension","liver_failure","nephrolith",          
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
# 1. Set up function
# ---------------------------------------------------------
run_ps_match_pipeline <- function(df, m = 5, seed = 123, replace = TRUE, caliper = 0.2, std.caliper = TRUE) {
  
  pred_matrix <- make.predictorMatrix(df)
  pred_matrix[, !( dimnames(pred_matrix)[[2]]  %in%  c(vars_cat, "age_at_index") )] <- 0
  #pred_matrix[, c(vars_cat, "age_at_index")] <- 1
  
  imputed <- mice(df, m = m, method = 'pmm', seed = seed, predictorMatrix = pred_matrix)
  comp_list <- complete(imputed, "all")
  
  ps_formula <- tamsulosin ~ age_at_index + acidosis + aids + alzheimers_disease +
    cancer + copd + stroke + rheum_disease + diabetes + heart_failure +
    hypercholesterolaemia + hypertension + liver_failure + nephrolith + paralysis +
    peptic_ulcer + pvd + ckd + anticoagulants + antidiabetics + antiemetics +
    antihypertensives + dutasteride + lipid_lowering + nsaids + opioids + snri +
    solifenacin + tadalafil + bmi_value + smk_status
 
   matched_list <- matchthem(ps_formula,
                       datasets    = imputed,
                       approach    = "within",
                       method      = "nearest",
                       distance    = "glm",
                       link        = "logit",
                       ratio       = 1,
                       replace     = replace,
                       caliper     = caliper,
                       std.caliper = TRUE
  )
  
  matched_list <- complete(matched_list,"all")
  matched_list <- lapply(matched_list,function(x)x[!is.na(x$subclass),])
  
  # ---- Incidence rates, computed once off the first matched imputation ----
  summary_data <- lapply(matched_list, function(x){
    x %>%
    group_by(tamsulosin) %>%
    summarise(
      total_cases          = sum(aSAH),
      total_follow_up       = sum(fu_days),
      total_follow_up_years = sum(fu_days) / 365.25,
      median_fu_days        = median(fu_days),
      .groups = "drop"
    ) %>%
    mutate(incidence_rate = (total_cases / total_follow_up_years) * 1000)
  })
  
  # ---- Cox model on each imputation, pooled ----
  cox_fits_crude <- lapply(matched_list, function(d) {
    coxph(Surv(fu_days, aSAH) ~ tamsulosin + strata(subclass), data = d)
  })
  cox_fit_crude <- as.mira(cox_fits_crude)
  cox_pool_crude <- pool(cox_fit_crude)
  
  list(
    matched_list   = matched_list,
    summary_data   = summary_data,
    cox_fit_crude  = cox_fit_crude,
    cox_pool_crude = cox_pool_crude,
    imputed = imputed
  )
}


#---------------------------------------
#Running the function
#---------------------------------------


alf_ref <- df[df$exposure %in% c(1,2), ]
fin_ref <- df[df$exposure %in% c(1,3), ]



alf_results<- run_ps_match_pipeline(alf_ref, replace=T) # the same control can be used for more cases

fin_results <- run_ps_match_pipeline(fin_ref, replace=T)



#---------------------------------------
#Outputting results
#---------------------------------------

#Alfuzosin
alf_hr <- tbl_regression(alf_results$cox_fit_crude, exponentiate = TRUE)
alf_hr %>% as_flex_table() %>% save_as_docx(path = "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Export\\alfuzosin_pp_cox.docx")
alf_inc <- as.data.frame(alf_results$summary_data)
alf_inc %>%  writexl::write_xlsx(path = "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Export\\alfuzosin_pp_inc.xlsx")

alf_results$matched_list[[1]] %>% count(tamsulosin)


#Finasteride
fin_hr <- tbl_regression(fin_results$cox_fit_crude, exponentiate = TRUE)
fin_hr %>% as_flex_table() %>% save_as_docx(path = "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Export\\finasteride_pp_cox.docx")
fin_inc <- as.data.frame(fin_results$summary_data)
fin_inc %>%  writexl::write_xlsx(path = "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Export\\finasteride_pp_inc.xlsx")

fin_results$matched_list[[1]] %>% count(tamsulosin)
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
#Matched Table One's and Balance Tables
#---------------------------------------


### for alfuzosin

matched_df <- alf_results$matched_list[[1]]

MatchedTable1 <- CreateTableOne(vars = vars, 
                         strata = "exposure", 
                         factorVars = vars_cat, data = matched_df)

print(MatchedTable1)
mt1export <- print(MatchedTable1, printToggle = FALSE, smd = TRUE, quote = FALSE, noSpaces = TRUE)
mt1export <- as.data.frame(mt1export) %>% rownames_to_column(var = "Variable")
ft <- flextable(mt1export) %>% bold(part = "header") %>% autofit()
save_as_docx(ft, path = "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Export\\alfuzosin_pp_matched_table1.docx")


### for finasteride

matched_df <- fin_results$matched_list[[1]]

MatchedTable1 <- CreateTableOne(vars = vars, 
                                strata = "exposure", 
                                factorVars = vars_cat, data = matched_df)



print(MatchedTable1)
mt1export <- print(MatchedTable1, printToggle = FALSE, smd = TRUE, quote = FALSE, noSpaces = TRUE)
mt1export <- as.data.frame(mt1export) %>% rownames_to_column(var = "Variable")
ft <- flextable(mt1export) %>% bold(part = "header") %>% autofit()
save_as_docx(ft, path = "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Export\\finasteride_pp_matched_table1.docx")


#---------------------------------------
# Propensity score graph
#---------------------------------------

### Imputed data

output_ps_plot <- function(drug_results, label) {
  

comp_list <- complete(drug_results$imputed, "all")
d <- comp_list[[1]]

ps_model <- glm(tamsulosin ~ age_at_index + acidosis + aids + alzheimers_disease +
                  cancer + copd + stroke + rheum_disease + diabetes + heart_failure +
                  hypercholesterolaemia + hypertension + liver_failure + nephrolith + paralysis +
                  peptic_ulcer + pvd + ckd + anticoagulants + antidiabetics + antiemetics +
                  antihypertensives + dutasteride + lipid_lowering + nsaids + opioids + snri +
                  solifenacin + tadalafil + bmi_value + smk_status, data = d, family = "binomial")
d$pscore <- predict(ps_model, type = "response")

imputed_plot <- ggplot(d, aes(x = pscore, fill = factor(tamsulosin))) +
  geom_density(alpha = 0.25, adjust = 2) +
  theme_minimal()+
  scale_fill_manual(values = c("0" = "blue", "1" = "red"), labels = c("Non-User", "User"))+
  ggtitle(paste0("Density plot for PS in unmatched", label, "cohort"))

### Matched data

matched_plot <- ggplot(drug_results$matched_list[[1]], aes(x = distance, fill = factor(tamsulosin))) +
  geom_density(alpha = 0.25, adjust = 2) +
  labs(x = "Propensity score", y = "Density", fill = "Tamsulosin user") +
  theme_minimal()+
  scale_fill_manual(values = c("0" = "blue", "1" = "red"), labels = c("Non-User", "User"))+
  ggtitle(paste0("Density plot for PS in matched", label, "cohort"))

ggsave(file.path("C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Export", paste0("density_ps_imputed_", label, ".png")),
       plot = imputed_plot,
       dpi = 300)

ggsave(file.path("C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Export", paste0("density_ps_matched_", label, ".png")),
       plot = matched_plot,
       dpi = 300)

}


output_ps_plot(drug_results = alf_results, label = "alfuzosin")
output_ps_plot(drug_results = fin_results, label = "finasteride")
