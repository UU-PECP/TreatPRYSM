
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



Table1 <- CreateTableOne(vars = c(vars_cat,vars_num), 
                         strata = "exposure", 
                         factorVars =vars_cat , data = df)

print(Table1)
t1export <- print(Table1, printToggle = FALSE, smd = TRUE, quote = FALSE, noSpaces = TRUE)
t1export <- as.data.frame(t1export) %>% rownames_to_column(var = "Variable")
ft <- flextable(t1export) %>% bold(part = "header") %>% autofit()
save_as_docx(ft, path = "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Export\\tamsulosin_pp_table1.docx")
# ---------------------------------------------------------
# 1. Set up function
# ---------------------------------------------------------

run_ps_match_no_imput_pipeline <- function(df, replace=F, caliper = 0.2) { 
  
  #Incidence rates
  summary_data <- df %>%
    group_by(tamsulosin) %>%
    summarise(
      total_cases = sum(aSAH),
      total_follow_up = sum(fu_days),
      total_follow_up_years = sum(fu_days) / 365.25,
      median_fu_days = median(fu_days),
    )
  
  summary_data <- summary_data %>%
    mutate(
      incidence_rate = (total_cases / total_follow_up_years) * 1000
    )
  
 
  ps_formula <- tamsulosin ~ age_at_index + acidosis + aids + alzheimers_disease +
    cancer + copd + stroke + rheum_disease + diabetes + heart_failure +
    hypercholesterolaemia + hypertension + liver_failure + nephrolith + paralysis +
    peptic_ulcer + pvd + ckd +  anticoagulants + antidiabetics + antiemetics +        
    antihypertensives + dutasteride + lipid_lowering + nsaids + opioids + snri + solifenacin + tadalafil
  
  # match within each imputation -> mimids object
  matched <- matchit(ps_formula,
                       data    = df,
                       method      = "nearest",
                       distance    = "glm",
                       link        = "logit",
                       ratio       = 1,
                       replace     = replace,
                       caliper     = caliper,
                       std.caliper = TRUE
  )
  
  matched <- get_matches(matched)
  
  cox_fit_crude <- with(matched,
                        coxph(Surv(fu_days, aSAH) ~ tamsulosin + strata(subclass))
  )
  
  list(matched        = matched,
       cox_fit_crude  = cox_fit_crude,
       summary_data = summary_data)
}

run_ps_match_imput_pipeline <- function(df, replace=F, m = 5, seed = 123, caliper = 0.2) {  
  
  #Incidence rates
  summary_data <- df %>%
    group_by(tamsulosin) %>%
    summarise(
      total_cases = sum(aSAH),
      total_follow_up = sum(fu_days),
      total_follow_up_years = sum(fu_days) / 365.25,
      median_fu_days = median(fu_days),
    )
  
  summary_data <- summary_data %>%
    mutate(
      incidence_rate = (total_cases / total_follow_up_years) * 1000
    )
  
  imputed <- mice(df, m = m, seed = seed, 
                  method = 'pmm'   #???
                  # ,formalas    = list(
                  #   smk_status = ....,
                  #   bmi_value  = .... 
                  # )
  )
  
  ps_formula <- tamsulosin ~ age_at_index + acidosis + aids + alzheimers_disease +
    cancer + copd + stroke + rheum_disease + diabetes + heart_failure +
    hypercholesterolaemia + hypertension + liver_failure + nephrolith + paralysis +
    peptic_ulcer + pvd + ckd + bmi_value + smk_status + anticoagulants + antidiabetics + antiemetics +        
    antihypertensives + dutasteride + lipid_lowering + nsaids + opioids + snri + solifenacin + tadalafil
  
  # match within each imputation -> mimids object
  matched <- matchthem(ps_formula,
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
  
  matched <- complete(matched,"all")
  matched <- lapply(matched,function(x)x[!is.na(x$subclass),])

  cox_fit_crude <- lapply(matched,
                        function(x) coxph(Surv(fu_days, aSAH) ~ tamsulosin + strata(subclass), data=x)  )
  
  
  list(imputed        = imputed,
       matched        = matched,
       cox_fit_crude  = cox_fit_crude,
       #cox_pool_crude = pool(cox_fit_crude),
       summary_data = summary_data)
}


#---------------------------------------
#Running the function
#---------------------------------------


alf_ref <- df %>% filter(exposure == 1 | exposure == 2)
fin_ref <- df %>% filter(exposure == 1 | exposure == 3)
# alf_ref <- df[df$exposure %in% c(1,2), ]
# fin_ref <- df[df$exposure %in% c(1,3), ]

# alf_ref
df_alf_results_less_matched_F <- run_ps_match_no_imput_pipeline(alf_ref[1:1000,], replace=F)
df_alf_results_less_matched_T <- run_ps_match_no_imput_pipeline(alf_ref[1:1000,], replace=T)

alf_results_less_matched <- run_ps_match_imput_pipeline(alf_ref[1:1000,], replace=F)
alf_results_multiple_controls <- run_ps_match_imput_pipeline(alf_ref[1:1000,], replace=T) # the same control can be used for more cases

fin_results <- run_ps_match_imput_pipeline(fin_ref)

#---------------------------------------
#Outputting results
#---------------------------------------


alf_hr <- tbl_regression(alf_results$cox_fit_crude, exponentiate = TRUE)
alf_hr %>% as_flex_table() %>% save_as_docx(path = "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Export\\alfuzosin_pp_cox.docx")
alf_inc <- as.data.frame(alf_results$summary_data)
alf_inc %>%  writexl::write_xlsx(path = "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Export\\alfuzosin_pp_inc.xlsx")

fin_hr <- tbl_regression(fin_results$cox_fit_crude, exponentiate = TRUE)
fin_hr %>% as_flex_table() %>% save_as_docx(path = "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Export\\finasteride_pp_cox.docx")
fin_inc <- as.data.frame(alf_results$summary_data)
fin_inc %>%  writexl::write_xlsx(path = "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Export\\finasteride_pp_inc.xlsx")
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


ggsave(gg_crude, dpi = 300, path = "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Export\\tamsulosin_km.png")

#---------------------------------------
#Sanity Checking balance and sample size
#---------------------------------------

bal.tab(alf_results$matched, un = TRUE)      # SMDs before/after, pooled across imputations
love.plot(alf_results$matched, threshold = 0.1)
summary(alf_results$matched)   # matched/unmatched counts per imputation


### for alfuzosin

MatchedTable1 <- CreateTableOne(vars = vars, 
                         strata = "exposure", 
                         factorVars = c("acidosis","aids","alcohol","alzheimers_disease",
                                        "cancer","copd","stroke","rheum_disease","diabetes","heart_failure",        
                                        "hypercholesterolaemia","hypertension","liver_failure","nephrolith",          
                                        "paralysis","peptic_ulcer","pvd","ckd","anticoagulants","antidiabetics","antiemetics",        
                                        "antihypertensives","dutasteride","lipid_lowering", "nsaids","opioids",                      
                                        "snri","solifenacin","tadalafil","smk_status"), data = alf_results$matched)

print(MatchedTable1)
mt1export <- print(MatchedTable1, printToggle = FALSE, smd = TRUE, quote = FALSE, noSpaces = TRUE)
mt1export <- as.data.frame(mt1export) %>% rownames_to_column(var = "Variable")
ft <- flextable(mt1export) %>% bold(part = "header") %>% autofit()
save_as_docx(ft, path = "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Export\\alfuzosin_pp_matched_table1.docx")

### for finasteride

MatchedTable1 <- CreateTableOne(vars = vars, 
                                strata = "exposure", 
                                factorVars = c("acidosis","aids","alcohol","alzheimers_disease",
                                               "cancer","copd","stroke","rheum_disease","diabetes","heart_failure",        
                                               "hypercholesterolaemia","hypertension","liver_failure","nephrolith",          
                                               "paralysis","peptic_ulcer","pvd","ckd","anticoagulants","antidiabetics","antiemetics",        
                                               "antihypertensives","dutasteride","lipid_lowering", "nsaids","opioids",                      
                                               "snri","solifenacin","tadalafil","smk_status"), data = fin_results$matched)

print(MatchedTable1)
mt1export <- print(MatchedTable1, printToggle = FALSE, smd = TRUE, quote = FALSE, noSpaces = TRUE)
mt1export <- as.data.frame(mt1export) %>% rownames_to_column(var = "Variable")
ft <- flextable(mt1export) %>% bold(part = "header") %>% autofit()
save_as_docx(ft, path = "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Export\\finasteride_pp_matched_table1.docx")
