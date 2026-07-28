
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
library(gtsummary)
library(janitor)

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

Table1 <- df %>% tbl_summary(by = exposure)

# ---------------------------------------------------------
# 1. Set up function
# ---------------------------------------------------------

run_ps_cox_pipeline <- function(df, m = 5, seed = 123) {
  
  
  # ---------------------------------------------------------
  # 2. Impute
  # ---------------------------------------------------------
  imputed <- mice(df, m = m, method = 'pmm', seed = seed)
  
  # ---------------------------------------------------------
  # 3. PS model across all imputations
  # ---------------------------------------------------------
  ps_fits <- with(
    imputed,
    glm(tamsulosin ~ age_at_index + acidosis + aids + alzheimers_disease + cancer + copd +
          stroke + rheum_disease + diabetes + heart_failure + hypercholesterolaemia + hypertension +
          liver_failure + paralysis + peptic_ulcer + pvd + ckd + bmi_value + smk_status + nephrolith,
        family = binomial)
  )
  
  # ---------------------------------------------------------
  # 4. Attach pscore back into the mids object (explicit loop,
  #    no cur_group_id() ambiguity)
  # ---------------------------------------------------------
  long_df <- mice::complete(imputed, "long", include = TRUE)
  
  for (i in seq_len(m)) {
    rows <- which(long_df$.imp == i)
    long_df$pscore[rows] <- predict(ps_fits$analyses[[i]], type = "response")
  }
  # .imp == 0 (the original, unimputed data) has no pscore leave as NA
  
  imputed <- as.mids(long_df)
  
  # ---------------------------------------------------------
  # 5. Crude Cox model
  # ---------------------------------------------------------
  cox_fit_crude <- with(imputed, coxph(Surv(fu_days, aSAH) ~ tamsulosin))
  cox_pool_crude <- pool(cox_fit_crude)
  
  # ---------------------------------------------------------
  # 6. PS-adjusted Cox model
  # ---------------------------------------------------------
  cox_fit_adj <- with(imputed, coxph(Surv(fu_days, aSAH) ~ tamsulosin + pscore))
  cox_pool_adj <- pool(cox_fit_adj)
  
  # ---------------------------------------------------------
  # Return everything useful for downstream inspection/reporting
  # ---------------------------------------------------------
  list(
    imputed = imputed,
    ps_fits = ps_fits,
    cox_fit_crude = cox_fit_crude,
    cox_pool_crude = cox_pool_crude,
    cox_fit_adj = cox_fit_adj,
    cox_pool_adj = cox_pool_adj
  )
}


#---------------------------------------
#Running the function
#---------------------------------------


alf_ref <- df %>% filter(exposure == 1 | exposure == 2)
fin_ref <- df %>% filter(exposure == 1 | exposure == 3)


alf_results <- run_ps_cox_pipeline(alf_ref)
fin_results <- run_ps_cox_pipeline(fin_ref)

#---------------------------------------
#Outputting results
#---------------------------------------


tbl_regression(fin_results$cox_fit_adj, exponentiate = TRUE)
tbl_regression(fin_results$cox_fit_crude, exponentiate = TRUE)

tbl_regression(alf_results$cox_fit_adj, exponentiate = TRUE)
tbl_regression(alf_results$cox_fit_crude, exponentiate = TRUE)

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


print(gg_crude)
