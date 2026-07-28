library(haven)
library(lubridate)   # for the year() helper
library(MatchIt)
library(mice)
library(data.table)
library(dplyr)
library(ggplot2)
library(scales)      # for nicer axis labels
library(survival)
library(survminer)
library(tableone)

#read the datasets
df <- read_sas('../Output/amlodipine_ot_final.sas7bdat')
sapply(df, class)

df$amlodipine <- ifelse(df$index_exposure == "Amlodipine", 1, 0) #make amlodipine the explicit exposure

#drop variables no longer needed
df <- df %>%
  select(-last_coverage_period_start, -last_coverage_period_end, -aSAH_hosp_dt,
         -days_since_last_treatment, -yob, -index_exposure)

individual_data <- df %>%
  group_by(patid) %>%
  summarise(
    amlodipine = min(amlodipine),
    index_date = min(index_date),
    end_of_fu = min(end_of_fu),
    fu_days = min(fu_days),
    aSAH = max(aSAH_within_interval)
  )

#Incidence rates
summary_data <- individual_data %>%
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

print(summary_data)

sink("amlodipine_ot_incidence.txt")
print(summary_data)
sink()

# Create the Surv object
surv_object <- Surv(time = individual_data$fu_days, event = individual_data$aSAH)

# Develop the Cox regression model
cox_model <- coxph(Surv(time = fu_days, event = aSAH) ~ amlodipine,
                   data = individual_data)

sink("amlodipine_ot_cox.txt")
summary(cox_model)
sink()

#Plot incidence over time for both users.
# Kaplan-Meier stratified by exposure
surv_fit <- survfit(Surv(fu_days, aSAH) ~ amlodipine,
                    data = individual_data)

gg_crude <- ggsurvplot(
  surv_fit,
  fun = "event",
  conf.int = TRUE,
  censor = FALSE,
  break.time.by = 365,
  xlab = "Follow-up (days)",
  ylab = "Cumulative incidence of aSAH",
  legend.labs = c("OtherDihydropyridine", "Amlodipine"),
  palette = c("#1b9e77", "#d95f02"),
  ggtheme = theme_minimal(base_size = 12),
  risk.table = TRUE,
  risk.table.height = 0.25,
  risk.table.y.text.col = TRUE,
  ylim = c(0, 0.01)
)

## customise y-axis on the ggplot inside the object
gg_crude$plot <- gg_crude$plot +
  scale_y_continuous(
    labels = scales::percent_format(accuracy = 0.01),
    breaks = seq(0, 01, 0.0005)
  )

ggsave("amlodipine_ot_km.png", plot = gg_crude$plot, width = 8, height = 6, dpi = 300)

## Plot BP over time ##

# Fill missing values for BMI and (Sys | Dia) BP with individual median

View(head(df, 5000))
sum(is.na(df$bmi_value))
sum(is.na(df$diastol_BP))
sum(is.na(df$systol_BP))

# Fill by median per patient. If each value is missing per patient, keep it nan.
df_filled <- df %>%
  group_by(patid) %>%
  mutate(across(c(bmi_value, diastol_BP, systol_BP),
                ~ ifelse(is.na(.x),
                         ifelse(is.nan(median(.x, na.rm = TRUE)), NA, median(.x, na.rm = TRUE)),
                         .x))) %>%
  ungroup()

#Still quite a few missings but not too many.
sum(is.na(df_filled$bmi_value))
sum(is.na(df_filled$diastol_BP))
sum(is.na(df_filled$systol_BP))

# --- 1·1  Final-outcome flag (patient level) ----
df <- df %>%                                       # your long data frame
  group_by(patid) %>%
  mutate(ever_aSAH = any(aSAH_within_interval == 1)) %>%
  ungroup()

bp_vars <- c("patid", "interval_window_start", "amlodipine", "index_date", "interval_window_end",
             "ever_aSAH",               # for the ever_aSAH flag
             "diastol_BP", "systol_BP")            # the only two measures we plot

df_bp <- df_filled %>% select(all_of(bp_vars))

# --- 1·2  Time axis in months from index ----
df_bp <- df_bp %>%
  mutate(
    t_months_start = as.numeric(interval_window_start - index_date) / 30,
    t_months_end   = as.numeric(interval_window_end   - index_date) / 30,
    amlodipine_lbl = factor(amlodipine, labels = c("No","Yes")),
    outcome_lbl    = if_else(ever_aSAH, "Ever aSAH", "No aSAH")
  )

setDT(df_bp)

df_int <- df_bp[ , .(
  diastol_BP = mean(diastol_BP, na.rm = TRUE),
  systol_BP = mean(systol_BP, na.rm = TRUE)
), by = .(patid, t_months_start, amlodipine_lbl, outcome_lbl)]


df_long <- tidyr::pivot_longer(
  df_int,                                   # first argument = data
  cols      = c(diastol_BP, systol_BP),
  names_to  = "bp_type",
  values_to = "bp"
)

median_hilow <- function(x, ...) {
  qs <- quantile(x, c(.025, .5, .975), na.rm = TRUE)
  names(qs) <- c("ymin", "y", "ymax")
  qs
}

bp_plot <- ggplot(df_long,
                  aes(x = t_months_start, y = bp,
                      colour = amlodipine_lbl,
                      group = interaction(amlodipine_lbl, bp_type))) +
  stat_summary(
    fun.data = median_hilow, geom = "smooth",
    linewidth = 0.8, alpha = 0.2, se = TRUE, span = 0.4
  ) +
  facet_grid(
    outcome_lbl ~ bp_type, scales = "free_y",
    labeller = labeller(
      bp_type = c(diastol_BP = "Diastolic (mmHg)",
                  systol_BP  = "Systolic (mmHg)")
    )
  ) +
  labs(
    x = "Months since index date",
    y = "Blood pressure",
    colour = "On Amlodipine?"
  ) +
  scale_colour_brewer(palette = "Set1") +
  theme_bw()

## -------------------------------------------------------------
##  Save to disk: 300 dpi, 8 × 6 inches
## -------------------------------------------------------------
ggsave(
  filename = "amlodipine_ot_bp.png",
  plot     = bp_plot,
  width    = 8,            # inches
  height   = 6,            # inches
  dpi      = 300
)

# 1. columns strictly required for the model ----------------------
keep <- c("patid",
          "interval_window_start", "interval_window_end", "index_date",
          "aSAH_within_interval",
          "treatment_recency_status",          # categorical: Past / Recent / Current
          "amlodipine",                 # baseline exposure
          "diastol_BP", "systol_BP",    # time-varying confounders
          "age_at_interval_start",
          "gender", "deprivation_decile")

setDT(df_filled)[ , (setdiff(names(df_filled), keep)) := NULL ]     # trims in place

# 2. counting-process times and compact encodings -----------------
df_cox <- copy(df_filled)[ , `:=`(
  ## start / stop in days from index_date
  tstart  = as.numeric(interval_window_start - index_date),
  tstop   = as.numeric(interval_window_end   - index_date),
  
  ## categorical recency kept as factor (ordered for clarity)
  rec_fac = factor(treatment_recency_status,
                   levels = c("Past","Recent","Current")),
  
  ## small baseline covariates as ints (memory-efficient)
  sex_i   = as.integer(factor(gender)) - 1L,          # 0/1
  ses_i   = as.integer(factor(deprivation_decile))
)][ , c("interval_window_start","interval_window_end",
        "index_date","treatment_recency_status",
        "gender","deprivation_decile") := NULL ]    # drop originals

setorder(df_cox, tstop)   # Cox PH prefers sorted stop times

rm(df)
rm(df_filled)
rm(individual_data)
rm(df_bp)
rm(df_int)
rm(df_long)
gc()


## ================================================================
##  Fit Cox model  (rec_fac categorical, ref = "former")
##  - design matrix, model frame & y omitted to save RAM
## ================================================================
cox_fit <- coxph(
  Surv(tstart, tstop, aSAH_within_interval) ~
    relevel(rec_fac, ref = "Past")  +   # HRs: recent vs former, current vs former
    amlodipine                         +   # baseline exposure group
    diastol_BP + systol_BP             +   # time-varying covariates
    age_at_interval_start + sex_i + ses_i, # baseline covariates
  data    = df_cox,
  cluster = patid,              # robust SEs for within-patient correlation
  ties    = "breslow",          # lighter than 'efron'
  x = FALSE, y = FALSE, model = FALSE,  # don't store big objects
  robust  = TRUE,
  control = coxph.control(timefix = FALSE, iter.max = 20)
)

sink("amlodipine_ot_recency.txt")
print(summary(cox_fit))
sink()

df_asah <- df_cox[df_cox$aSAH_within_interval == 1]

summary_stats <- df_asah %>%
  group_by(amlodipine) %>%
  summarise(
    mean_sysbp = mean(systol_BP, na.rm = TRUE),
    sd_sysbp = sd(systol_BP, na.rm = TRUE),
    mean_diabp = mean(diastol_BP, na.rm = TRUE),
    sd_diabp = sd(diastol_BP, na.rm = TRUE)
  )

sink("amlodipine_ot_bp_before_asah.txt")
summary_stats
sink()
