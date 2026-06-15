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

#read the datasets
df <- read_sas('../Output/amlodipine_pp_final.sas7bdat')
sapply(df, class)

#set datatypes
df$amlodipine <- ifelse(df$exposure == "Amlodipine", 1, 0) #make amlodipine the explicit exposure
df$gender <- as.factor(df$gender)

#Calculate age at index_date
df <- df %>% 
  mutate(
    age = year(index_date) - yob
  )

#drop variables no longer needed
df <- df %>%
  select(-patid, -index_date, -end_of_treatment, -tod, -yob, -baseline_dt,
         -deathdate, -lcd, -aSAH_hosp_dt, -aSAH_gp_dt, -end_of_fu, -exposure)

# Perform multiple imputation
imputed_datasets <- mice(df, m = 5, method = 'pmm', seed = 123)

# Complete the single imputed dataset
imputed_dataset <- complete(imputed_datasets, 1)

#TODO Show outcome in table2, not 1.
#test argument set to false
#Make unbalanced bold in table to highlight imbalance
t1 <- CreateTableOne(vars = names(imputed_dataset),
                     data = imputed_dataset,
                     strata = 'amlodipine',
                     factorVars = c("aSAH", "gender", "acute_renal_failure", "alcohol_abuse", "anal_fissures", "angina_pectoris", "anxiety_disorders", 
                                    "arrhythmia", "ascites", "cancer", "chronic_kidney_disease", "cirrhosis", "conduction_disorders", "copd", 
                                    "deep_vein_thrombosis", "depression", "diabetes", "diabetic_nephropathy", "essential_tremors", "glaucoma", 
                                    "glomerular_diseases", "heart_failure", "hypercalciuria", "hypercholesterolaemia", "hyperthrophic_cardiomyopathy", 
                                    "hyperthyroidism", "liver_failure", "migraines", "myocardial_infarction", "nephrotic_syndrome", "osteoporosis", 
                                    "parkinson", "pericarditis", "peripheral_vascular_disease", "portal_hypertension", "proteinuria_and_albuminuria", 
                                    "pulmonary_hypertension", "pulmonary_oedema", "raynauds_disease", "scleroderma", "stroke", 
                                    "venous_thromboembolism", 'smk_status'),
                     test = F,
                     smd = T)

t1 <- print(t1, printToggle = FALSE, smd = TRUE, quote = T, noSpaces = TRUE)
write.csv(t1, "amlodipine_pp_table1.csv", row.names = TRUE)

#Calculate propensity scores
#Currently has no interactions/non-linearities or splines etc.
#Can examine different balances after model adjustments (smg per strata (e.g. divide up in multiple propscore groups and compare smg per strata))

ps_model <- glm(amlodipine ~ gender + age + acute_renal_failure + alcohol_abuse + anal_fissures + angina_pectoris + anxiety_disorders + arrhythmia + 
                  ascites + cancer + chronic_kidney_disease + cirrhosis + conduction_disorders + copd + deep_vein_thrombosis + depression + 
                  diabetes + diabetic_nephropathy + essential_tremors + glaucoma + glomerular_diseases + heart_failure + hypercalciuria + 
                  hypercholesterolaemia + hyperthrophic_cardiomyopathy + hyperthyroidism + liver_failure + migraines + myocardial_infarction + 
                  nephrotic_syndrome + osteoporosis + parkinson + pericarditis + peripheral_vascular_disease + portal_hypertension + proteinuria_and_albuminuria + 
                  pulmonary_hypertension + pulmonary_oedema + raynauds_disease + scleroderma + stroke + venous_thromboembolism + bmi_value + smk_status + diastol_BP + systol_BP + n_consults,
                data = imputed_dataset, family = binomial)

summary(ps_model)
imputed_dataset$pscore <- predict(ps_model, type = "response")

# Plot the density of propensity scores by amlodipine with Gaussian smoothing
#A lot of overlap. May indicate that groups are already pretty similar, or that we miss important predictors.
#Distributions too similar.
#Range is very limited (should ideally go to 1)
#Double check variables as well and see whether variables transformed

density_plot  <-ggplot(imputed_dataset, aes(x = pscore, fill = factor(amlodipine))) +
  geom_density(alpha = 0.25, adjust = 2) +
  labs(title = "Density of Propensity Scores by Amlodipine User",
       x = "Propensity Score",
       y = "Density",
       fill = "Amlodipine user") +
  theme_minimal() +
  scale_fill_manual(values = c("0" = "blue", "1" = "red"), labels = c("Non-User", "User"))
ggsave("amlodipine_pp_propscore.png", plot = density_plot, width = 8, height = 6, dpi = 300)

#Incidence rates
summary_data <- imputed_dataset %>%
  group_by(amlodipine) %>%
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

sink("amlodipine_pp_incidence.txt")
print(summary_data)
sink()

#Unadjusted fit
cox_fit_crude <- with(
  imputed_datasets,
  coxph(Surv(fu_days, aSAH) ~ amlodipine)
)

cox_pool_crude <- pool(cox_fit_crude)
summary(cox_pool_crude)

#Adjusted fit
cox_fit_adj <- with(
  imputed_datasets,
  coxph(Surv(fu_days, aSAH) ~ amlodipine + deprivation_decile + 
          raynauds_disease + gender + age)
)

cox_pool_adj <- pool(cox_fit_adj)
summary(cox_pool_adj)


sink("amlodipine_pp_cox_pooled.txt")
summary(cox_pool_crude)
sink()

sink("amlodipine_pp_coxadj_pooled.txt")
summary(cox_pool_adj)
sink()

#Plot incidence over time for both users.
# Kaplan-Meier stratified by exposure
surv_fit <- survfit(Surv(fu_days, aSAH) ~ amlodipine,
                    data = imputed_dataset)

gg_crude <- ggsurvplot(
  surv_fit,
  fun = "event",
  conf.int = TRUE,
  censor = FALSE,
  break.time.by = 365,
  xlab = "Follow-up (days)",
  ylab = "Cumulative incidence of aSAH",
  legend.labs = c("OtherDHP", "Amlodipine"),
  palette = c("#d95f02", "#1b9e77"),
  ggtheme = theme_minimal(base_size = 12),
  risk.table = TRUE,
  risk.table.height = 0.25,
  risk.table.y.text.col = TRUE,
  ylim = c(0, 0.01)
)

## ?????? customise y-axis on the ggplot inside the object ??????
gg_crude$plot <- gg_crude$plot +
  scale_y_continuous(
    limits = c(0, 0.004),                 # explicit y-axis range
    breaks = seq(0, 0.01, 0.002),        # choose sensible spacing
    labels = scales::percent_format(accuracy = 0.01),
    expand = c(0, 0)                    # removes extra padding
  )

gg_crude

ggsave("amlodipine_pp_km.png", plot = gg_crude$plot, width = 8, height = 6, dpi = 300)

