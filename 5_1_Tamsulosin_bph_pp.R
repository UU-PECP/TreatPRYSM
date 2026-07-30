
library(tidyverse)
library(haven)
library(lubridate)   # for the year() helper
library(MatchIt)
library(mice)
library(dplyr)
library(ggplot2)
library(scales)      # for nicer axis labels
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
df$tamsulosin <- ifelse(df$exposure > 1, 0, 1) #make tamsulosin the explicit exposure



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

variable.names(df)


# descriptive table

vars <- c("acidosis","aids","alcohol","alzheimers_disease",
         "cancer","copd","stroke","rheum_disease","diabetes","heart_failure",        
"hypercholesterolaemia","hypertension","liver_failure","nephrolith",          
"paralysis","peptic_ulcer","pvd","ckd","anticoagulants","antidiabetics","antiemetics",        
"antihypertensives","dutasteride","lipid_lowering", "nsaids","opioids",                      
"snri","solifenacin","tadalafil","smk_status","bmi_value", "age_at_index")



Table1 <- CreateTableOne(vars = vars, 
                         strata = "exposure", 
                         factorVars = c("acidosis","aids","alcohol","alzheimers_disease",
                                        "cancer","copd","stroke","rheum_disease","diabetes","heart_failure",        
                                        "hypercholesterolaemia","hypertension","liver_failure","nephrolith",          
                                        "paralysis","peptic_ulcer","pvd","ckd","anticoagulants","antidiabetics","antiemetics",        
                                        "antihypertensives","dutasteride","lipid_lowering", "nsaids","opioids",                      
                                        "snri","solifenacin","tadalafil","smk_status"), data = df)

print(Table1)
t1export <- print(Table1, printToggle = FALSE, smd = TRUE, quote = FALSE, noSpaces = TRUE)
t1export <- as.data.frame(t1export) %>% rownames_to_column(var = "Variable")
ft <- flextable(t1export) %>% bold(part = "header") %>% autofit()
save_as_docx(ft, path = "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Export\\tamsulosin_pp_table1.docx")
# ---------------------------------------------------------
# 1. Set up function
# ---------------------------------------------------------

run_ps_match_pipeline <- function(df, m = 5, seed = 123, caliper = 0.2) {
  
  imputed <- mice(df, m = m, method = 'pmm', seed = seed)
  
  ps_formula <- tamsulosin ~ age_at_index + acidosis + aids + alzheimers_disease +
    cancer + copd + stroke + rheum_disease + diabetes + heart_failure +
    hypercholesterolaemia + hypertension + liver_failure + nephrolith + paralysis +
    peptic_ulcer + pvd + ckd + bmi_value + smk_status
  
  # match within each imputation -> mimids object
  matched <- matchthem(ps_formula,
                       datasets    = imputed,
                       approach    = "within",
                       method      = "nearest",
                       distance    = "glm",
                       link        = "logit",
                       ratio       = 1,
                       caliper     = caliper,
                       std.caliper = TRUE)
  
  cox_fit_crude <- with(matched,
                        coxph(Surv(fu_days, aSAH) ~ tamsulosin),
                        cluster = TRUE)
  
  
  list(imputed        = imputed,
       matched        = matched,
       cox_fit_crude  = cox_fit_crude,
       cox_pool_crude = pool(cox_fit_crude))
}


#---------------------------------------
#Running the function
#---------------------------------------


alf_ref <- df %>% filter(exposure == 1 | exposure == 2)
fin_ref <- df %>% filter(exposure == 1 | exposure == 3)


alf_results <- run_ps_match_pipeline(alf_ref)
fin_results <- run_ps_match_pipeline(fin_ref)

#---------------------------------------
#Outputting results
#---------------------------------------


alf_hr <- tbl_regression(alf_results$cox_fit_crude, exponentiate = TRUE)
alf_hr %>% as_flex_table() %>% save_as_docx(path = "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Export\\alfuzosin_pp_cox.docx")

fin_hr <- tbl_regression(fin_results$cox_fit_crude, exponentiate = TRUE)
fin_hr %>% as_flex_table() %>% save_as_docx(path = "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Export\\finasteride_pp_cox.docx")
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


ggsave(dpi = 300, path = "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Export\\tamsulosin_km.png")

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
