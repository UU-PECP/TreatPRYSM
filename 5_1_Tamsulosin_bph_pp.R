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
df <- read.csv("F:\\Users\\Wyatt003\\BPH_nephrolithiasis\\Output\\bph_perprotocol.csv")
sapply(df, class)

#set datatypes
df$tamsulosin <- ifelse(df$drugsubstancename == "Tamsulosin", 1, 0) #make tamsulosin the explicit exposure

#Calculate age at index_date
df <- df %>% 
  mutate(
    age = year(episode.start) - yob
  )

#drop variables no longer needed
df <- df %>%
  select(-patid, -episode.end, -lcd, -yob, -bph_dt, -gender,
         -cprd_ddate, -aSAH_gp_dt, -end_of_fu, -drugsubstancename, 
         -lsoa_e, -hes_apc_e, -gender, -linkyear)


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

sink("bph_pp_incidence.txt")
print(summary_data)
sink()

#Unadjusted fit
cox_fit_crude <- with(
  df,
  coxph(Surv(fu_days, aSAH) ~ tamsulosin)
)

summary(cox_fit_crude)



# Perform multiple imputation
imputed_datasets <- mice(df, m = 5, method = 'pmm', seed = 123)

# Complete the single imputed dataset
imputed_dataset <- complete(imputed_datasets, 1)

#TO DO Show outcome in table2, not 1.
#test argument set to false
#Make unbalanced bold in table to highlight imbalance
t1 <- CreateTableOne(vars = names(imputed_dataset),
                     data = imputed_dataset,
                     strata = 'tamsulosin',
                     factorVars = c("aSAH", "acidosis", "aids", "alzheimers", "cancer", "copd",
                                    "stroke", "rheumatological_disease",  "diabetes", "heart_failure", "hypercholesterolemia", "hypertension", 
                                    "liver_disease", "paralysis", "peptic_ulcer", "pvd", "ckd"),
                     test = F,
                     smd = T)

t1 <- print(t1, printToggle = FALSE, smd = TRUE, quote = T, noSpaces = TRUE)
write.csv(t1, "tamsulosin_pp_table1.csv", row.names = TRUE)

#Calculate propensity scores
#Currently has no interactions/non-linearities or splines etc.
#Can examine different balances after model adjustments (smg per strata (e.g. divide up in multiple propscore groups and compare smg per strata))

ps_model <- glm(drugsubstancename ~ age + acidosis + aids + alzheimers + cancer + copd +
                stroke + rheumatological_disease + diabetes + heart_failure + hypercholesterolemia + hypertension 
                liver_disease + paralysis + peptic_ulcer + pvd + ckd,
                data = imputed_dataset, family = binomial)

summary(ps_model)
imputed_dataset$pscore <- predict(ps_model, type = "response")

# Plot the density of propensity scores by tamsulosin with Gaussian smoothing
#A lot of overlap. May indicate that groups are already pretty similar, or that we miss important predictors.
#Distributions too similar.
#Range is very limited (should ideally go to 1)
#Double check variables as well and see whether variables transformed

density_plot  <-ggplot(imputed_dataset, aes(x = pscore, fill = factor(drugsubstancename))) +
  geom_density(alpha = 0.25, adjust = 2) +
  labs(title = "Density of Propensity Scores by Tamsulosin User",
       x = "Propensity Score",
       y = "Density",
       fill = "Tamsulosin user") +
  theme_minimal() +
  scale_fill_manual(values = c("0" = "blue", "1" = "red"), labels = c("Non-User", "User"))
ggsave("tamsulosin_pp_propscore.png", plot = density_plot, width = 8, height = 6, dpi = 300)

#unadjusted fit

cox_fit_crude <- with(
  df,
  coxph(Surv(fu_days, aSAH) ~ tamsulosin)
)

cox_pool_crude <- pool(cox_fit_crude)
summary(cox_pool_crude)

#Adjusted fit
cox_fit_adj <- with(
  imputed_datasets,
  coxph(Surv(fu_days, aSAH) ~ drugsubstancename + deprivation_decile + 
          raynauds_disease + gender + age)
)

cox_pool_adj <- pool(cox_fit_adj)
summary(cox_pool_adj)


sink("tamsulosin_pp_cox_pooled.txt")
summary(cox_pool_crude)
sink()

sink("tamsulosin_pp_coxadj_pooled.txt")
summary(cox_pool_adj)
sink()

#Plot incidence over time for both users.
# Kaplan-Meier stratified by exposure
surv_fit <- survfit(Surv(fu_days, aSAH) ~ drugsubstancename,
                    data = imputed_dataset)

gg_crude <- ggsurvplot(
  surv_fit,
  fun = "event",
  conf.int = TRUE,
  censor = FALSE,
  break.time.by = 365,
  xlab = "Follow-up (days)",
  ylab = "Cumulative incidence of aSAH",
  legend.labs = c("OtherDrug", "Tamsulosin"),
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

ggsave("tamsulosin_pp_km.png", plot = gg_crude$plot, width = 8, height = 6, dpi = 300)

