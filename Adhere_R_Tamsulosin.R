
library(tidyverse)

library(data.table)

library(haven)

library(AdhereR)

library(janitor)




bphdata <- read_sas("F:\\Users\\Wyatt003\\BPH_nephrolithiasis\\Output\\Bphdrugatc_1.sas7bdat")

drugs <- c("Tamsulosin", "Finasteride", "Alfuzosin")

treat_episode <- list()

for (drug in drugs) {
  
  df_drug <- bphdata %>% filter(drugsubstancename == drug)
  
  treat_episode[[drug]] <- compute.treatment.episodes(
    
    data = df_drug,
    
    ID.colname = "patid",
    
    event.date.colname = "issuedate",
    
    event.duration.colname = "duration",
    
    medication.class.colname = "ATC",
    
    carryover.within.obs.window = TRUE,
    
    carry.only.for.same.medication = TRUE,
    
    consider.dosage.change = FALSE,
    
    medication.change.means.new.treatment.episode = TRUE,
    
    dosage.change.means.new.treatment.episode = FALSE,
    
    maximum.permissible.gap = 30,
    
    maximum.permissible.gap.unit = "days",
    
    maximum.permissible.gap.append.to.episode = FALSE,
    
    followup.window.start = 0,
    
    followup.window.start.unit = "days",
    
    followup.window.duration = 365 * 20,
    
    followup.window.duration.unit = "days",
    
    event.interval.colname = "event.interval",
    
    gap.days.colname = "gap.days",
    
    date.format = "%Y-%m-%d",
    
    parallel.backend = "none",
    
    parallel.threads = "auto",
    
    suppress.warnings = FALSE,
    
    return.data.table = TRUE
    
  )
  
  
}

treat_epi_all <- bind_rows(treat_episode_, .id = "drugsubstancename")



