
## Loading packages

library(tidyverse)

library(data.table)

library(haven)

library(AdhereR)

library(janitor)

### Reading in data

bphdata_all <- read_sas("F:\\Users\\Wyatt003\\BPH_nephrolithiasis\\Output\\all_bph_episodes.sas7bdat")

bphdata <- bphdata_all %>% distinct(patid, issuedate, exposure, .keep_all = TRUE)
bphdata %>% group_by(exposure) %>% count()


drugs <- c(1,2,3)

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

write.csv(treat_epi_all, "F:\\Users\\Wyatt003\\BPH_nephrolithiasis\\Output\\bph_treatmentepisodes.csv", row.names = FALSE)

### Per protocol: keep only first coverage blocks (prioritizes first record in the case of multi-drug)

treat_epi_all <- read.csv("F:\\Users\\Wyatt003\\BPH_nephrolithiasis\\Output\\bph_treatmentepisodes.csv")

pp_epi <- treat_epi_all %>% group_by(patid) %>% 
                             slice_min(episode.start, n = 1, with_ties = FALSE) %>% 
                             ungroup() %>% mutate(patid = as.character(patid))

### Combine treatment episode info with base cohort
linkedids <- read.csv("C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Codelists\\LinkedPatients_tamsulosin.csv",
                      colClasses = c(patid = "character")) 
pp_epi <- semi_join(pp_epi, linkedids, by = "patid")

bph_cohort <- read_sas("F:\\Users\\Wyatt003\\BPH_nephrolithiasis\\Output\\bph_pp_ps_bmismk.sas7bdat")
bph_cohort <- bph_cohort %>% distinct(patid, .keep_all = TRUE) ## There are 763 petiants with 16 exact duplicates. The origin of this problem is probably in the create of linked_bph_cohort, but unsure.


bph_pp <- inner_join(pp_epi, bph_cohort, by = "patid")


### Apply end of follow-up rules


    #########

bph_pp <- bph_pp %>% 
  mutate(end_of_fu = lubridate::ymd(episode.end)) %>% 
  mutate(end_of_fu = end_of_fu %>% replace_when(
    !is.na(censordate) & censordate < end_of_fu & censordate > lubridate::ymd('2002-10-31') ~ censordate,
    !is.na(aSAH_gp_dt) & aSAH_gp_dt < end_of_fu & aSAH_gp_dt > lubridate::ymd('2002-10-31') ~ aSAH_gp_dt,
    lubridate::ymd('2025-03-31') < end_of_fu ~ lubridate::ymd('2025-03-31')
  )) %>% 
  mutate(aSAH = if_else(!is.na(aSAH_gp_dt) & aSAH_gp_dt <= end_of_fu, 1, 0)) %>% 
  mutate(fu_days = end_of_fu - baseline_dt + 1)

bph_filters <- bph_pp %>% 
  filter(episode.start > lubridate::ymd('2002-10-31')) %>% 
  filter(episode.start < end_of_fu)  %>%
  mutate(fu_days = ymd(end_of_fu) - ymd(episode.start))

test <- anti_join(bph_pp, bph_filters, by = "patid")


write.csv(bph_filters, "F:\\Users\\Wyatt003\\BPH_nephrolithiasis\\Output\\bph_perprotocol.csv", row.names = FALSE)

##############################################
######## THIS IS ACTUALLY FILE 5_1 COPY PASTED FOR EASE OF RUNNING THE FILES AT THE SAME TIME!
##############################################
