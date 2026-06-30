
## Loading packages

library(tidyverse)

library(data.table)

library(haven)

library(AdhereR)

library(janitor)


### Reading in data

bphdata <- read_sas("F:\\Users\\Wyatt003\\BPH_nephrolithiasis\\Output\\All_bph_drugissue_linked.sas7bdat")
n_distinct(bphdata$patid)

drugs <- c("Tamsulosin", "Finasteride", "Alfuzosin")

### Generating treatment episodes for each drug seperately

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

### Bind together the three drugs with labelled substance name per episode.

treat_epi_all <- bind_rows(treat_episode, .id = "drugsubstancename")

write.csv(treat_epi_all, "F:\\Users\\Wyatt003\\BPH_nephrolithiasis\\Output\\bph_treatmentepisodes.csv")
treat_epi_all <- read.csv("F:\\Users\\Wyatt003\\BPH_nephrolithiasis\\Output\\bph_treatmentepisodes.csv")
### Per protocol: keep only first coverage blocks (prioritizes first record in the case of multi-drug)

bph_pp <- treat_epi_all %>% filter(episode.ID == 1) %>% mutate(patid = as.character(patid))
n_distinct(bph_pp$patid)

bph_pp <- bph_pp %>% 
  group_by(patid) %>% 
  slice_min(episode.start, n=1, with_ties = FALSE) %>% 
  ungroup()

### Combine treatment episode info with base cohort

bph_cohort <- read_sas("F:\\Users\\Wyatt003\\BPH_nephrolithiasis\\Output\\bph_cohort.sas7bdat")

bph_pp <- left_join(bph_pp, bph_cohort, by = "patid")

### Apply end of follow-up rules


bph_pp <- bph_pp %>% 
  mutate(end_of_fu = lubridate::ymd(episode.end)) %>% 
  mutate(end_of_fu = end_of_fu %>% replace_when(
    !is.na(censordate) & censordate < end_of_fu & censordate > lubridate::ymd('2002-10-31') ~ censordate,
    !is.na(aSAH_gp_dt) & aSAH_gp_dt < end_of_fu & aSAH_gp_dt > lubridate::ymd('2002-10-31') ~ aSAH_gp_dt,
    lubridate::ymd('2025-03-31') < end_of_fu ~ lubridate::ymd('2025-03-31')
  )) %>% 
  mutate(aSAH = if_else(!is.na(aSAH_gp_dt) & aSAH_gp_dt <= end_of_fu, 1, 0)) %>% 
  mutate(fu_days = end_of_fu - bph_dt + 1)

bph_filters <- bph_pp %>% 
  filter(episode.start < end_of_fu) %>% 
  filter(end_of_fu > episode.start) %>% 
  filter(episode.start > lubridate::ymd('2002-10-31'))


write.csv(bph_pp, "F:\\Users\\Wyatt003\\BPH_nephrolithiasis\\Output\\bph_perprotocol.csv")

