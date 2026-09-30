
## Loading packages

library(tidyverse)

library(data.table)

library(haven)

library(AdhereR)

library(janitor)


### Reading in data

nldata <- read_sas("F:\\Users\\Wyatt003\\Tamsulosin\\Output\\All_nl_drugissue.sas7bdat")

nldata <- nldata %>% mutate(drugsubstancename = if_else(drugsubstancename == "", "None", drugsubstancename))

n_distinct(bphdata$patid)

drugs <- c("Tamsulosin", "Analgesic", "None")

### Generating treatment episodes for each drug seperately

treat_episode <- list()

for (drug in drugs) {
  
  df_drug <- nldata %>% filter(drugsubstancename == drug)
  
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

### Bind together the three drugs with labelled substance name per episode.

treat_epi_all <- bind_rows(treat_episode, .id = "drugsubstancename")



write.csv(treat_epi_all, "F:\\Users\\Wyatt003\\Tamsulosin\\Output\\nl_treatmentepisodes.csv")
treat_epi_all <- read.csv("F:\\Users\\Wyatt003\\Tamsulosin\\Output\\nl_treatmentepisodes.csv")
### Per protocol: keep only first coverage blocks (prioritizes first record in the case of multi-drug)

nl_pp <- treat_epi_all %>% filter(episode.ID == 1) %>% mutate(patid = as.character(patid))
n_distinct(nl_pp$patid)

nl_pp <- nl_pp %>% 
  group_by(patid) %>% 
  slice_min(episode.start, n=1, with_ties = FALSE) %>% 
  ungroup()

### Combine treatment episode info with base cohort

nl_cohort <- read_sas("F:\\Users\\Wyatt003\\Tamsulosin\\Output\\nl_cohort.sas7bdat")

nl_pp <- right_join(nl_pp, nl_cohort, by = "patid")

### Apply end of follow-up rules


bph_pp <- bph_pp %>% 
  mutate(end_of_fu = lubridate::ymd(episode.end)) %>% 
  mutate(end_of_fu = end_of_fu %>% replace_when(
    !is.na(regenddate) & regenddate < end_of_fu & regenddate > lubridate::ymd('2002-10-31') ~ regenddate,
    !is.na(cprd_ddate) & cprd_ddate < end_of_fu & cprd_ddate > lubridate::ymd('2002-10-31') ~ cprd_ddate,
    !is.na(aSAH_gp_dt) & aSAH_gp_dt < end_of_fu & aSAH_gp_dt > lubridate::ymd('2002-10-31') ~ aSAH_gp_dt,
    !is.na(lcd) & cprd_ddate < end_of_fu & regenddate > lubridate::ymd('2002-10-31') ~ lcd,
    lubridate::ymd('2025-03-31') < end_of_fu ~ lubridate::ymd('2025-03-31')
  )) %>% 
  mutate(aSAH = if_else(!is.na(aSAH_gp_dt) & aSAH_gp_dt <= end_of_fu, 1, 0)) %>% 
  mutate(fu_days = end_of_fu - bph_dt + 1)

bph_filters <- bph_pp %>% 
  filter(episode.start < end_of_fu) %>% 
  filter(end_of_fu > episode.start) %>% 
  filter(episode.start > lubridate::ymd('2002-10-31'))


write.csv(bph_pp, "F:\\Users\\Wyatt003\\Tamsulosin\\Output\\bph_perprotocol.csv")

