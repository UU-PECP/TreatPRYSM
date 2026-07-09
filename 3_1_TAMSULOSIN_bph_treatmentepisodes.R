
## Loading packages

library(tidyverse)

library(data.table)

library(haven)

library(AdhereR)

library(janitor)

### Reading in data

bphdata <- read_sas("F:\\Users\\Wyatt003\\BPH_nephrolithiasis\\Output\\all_bph_episodes.sas7bdat")
n_distinct(bphdata$patid)


drugs <- c(1, 2, 3)

### Generating treatment episodes for each drug separately

treat_episode <- list()

for (drug in drugs) {
  
  df_drug <- bphdata %>% filter(exposure == drug)
  
  treat_episode[[drug]] <- compute.treatment.episodes(
    
    data = df_drug,
    
    ID.colname = "patid",
    
    event.date.colname = "issuedate",
    
    event.duration.colname = "assumed_duration",
    
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

treat_epi_all <- bind_rows(treat_episode, .id = "exposure")

write.csv(treat_epi_all, "F:\\Users\\Wyatt003\\BPH_nephrolithiasis\\Output\\bph_treatmentepisodes.csv")
treat_epi_all <- read.csv("F:\\Users\\Wyatt003\\BPH_nephrolithiasis\\Output\\bph_treatmentepisodes.csv")
### Per protocol: keep only first coverage blocks (prioritizes first record in the case of multi-drug)

pp_epi <- treat_epi_all %>% group_by(patid) %>% 
                             slice_min(episode.start, n = 1, with_ties = FALSE) %>% 
                             ungroup() 

## Sanity tests
n_distinct(pp_epi$patid) # exactly the same number of unique patids identified in file 2_1
pp_epi %>% mutate(futuredates = if_else(episode.end > ymd("2025-03-31"), "yes", "no")) %>% tabyl(futuredates)

future <- pp_epi %>% mutate(futuredates = if_else(episode.end > ymd("2025-03-31"), "yes", "no")) %>% filter(futuredates == "yes")

sub1 <- bphdata %>% filter(patid == 822820018)
sub2 <- bphdata %>% filter(patid == 2046120545)
sub3 <- bphdata %>% filter(patid == 160390220164)



### Combine treatment episode info with base cohort
linkedids <- read_sas("F:\\Users\\Wyatt003\\BPH_nephrolithiasis\\Output\\linked_bph_cohort.sas7bdat")
pp_epi <- semi_join(pp_epi, linkedids, by = "patid")

bph_cohort <- read_sas("F:\\Users\\Wyatt003\\BPH_nephrolithiasis\\Output\\bph_pp_propscore.sas7bdat")
## ^ This is old, need to re-run with alcohol

bph_pp <- inner_join(bph_pp, bph_cohort, by = "patid")

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

