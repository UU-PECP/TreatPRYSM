## the Treat-PRYSM project
## Drug - Metformin
##
## File 4_0: Treatment episode construction - SHARED BODY
## Modelled on tamsulosin/4_1_TAMSULOSIN_bph_treatmentepisodes.R.
## source() this from a per-cohort driver (4_1/4_2) that has already
## set the variables below. Do not run this file directly.
##
## Required variables from the driver:
##   cohort_label        - e.g. "su" / "sglt2i"
##   episodes_sas_path    - path to output.all_<cohort>_episodes.sas7bdat
##   ps_final_sas_path     - path to output.<cohort>_ps_final.sas7bdat (3_3_0 output)
##   base_cohort_sas_path  - path to output.t2dm_cohort.sas7bdat (for yob, censordate, aSAH_apc_dt)
##   study_start_date      - character "YYYY-MM-DD", overall study start (used to floor end_of_fu)
##   study_end_date        - character "YYYY-MM-DD", overall study end (used to cap end_of_fu)
##   followup_window_years - max plausible follow-up length for AdhereR (index date to study_end_date)
##   episodes_csv_path      - where to write/read the intermediate treatment-episode csv
##   perprotocol_csv_path   - where to write the final per-protocol dataset

## Loading packages

library(tidyverse)
library(data.table)
library(haven)
library(AdhereR)
library(janitor)

### Reading in data

metdata_all <- read_sas(episodes_sas_path)

metdata <- metdata_all %>% distinct(patid, issuedate, exposure, .keep_all = TRUE)
metdata %>% group_by(exposure) %>% count()

drugs <- c(1, 2)  ## 1 = metformin, 2 = comparator (SU or SGLT2i, per driver)

### splitting the data into chunks by patid

chunks <- split(metdata, as.integer(factor(metdata$patid)) %% 20)

### Generating treatment episodes for each drug separately

treat_episode <- list()

for (drug in drugs) {
  out <- list()
  for (k in seq_along(chunks)) {

  df_drug <- chunks[[k]][chunks[[k]]$exposure == drug, ]

  out[[k]] <- compute.treatment.episodes(

    data = df_drug,

    ID.colname = "patid",

    event.date.colname = "issuedate",

    event.duration.colname = "assumed_duration",

    medication.class.colname = "exposure",

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

    followup.window.duration = 365 * followup_window_years,

    followup.window.duration.unit = "days",

    event.interval.colname = "event.interval",

    gap.days.colname = "gap.days",

    date.format = "%Y-%m-%d",

    parallel.backend = "none",

    parallel.threads = "auto",

    suppress.warnings = FALSE,

    return.data.table = TRUE

  )
  cat("cohort", cohort_label, "drug", drug, "chunk", k, "\n") ## counts progress by chunk and drug
  }
  treat_episode[[drug]] <- rbindlist(out)
}

### Bind together the two drugs (metformin, comparator) with labelled exposure per episode.

treat_epi_all <- bind_rows(treat_episode, .id = "exposure") %>%
  mutate(patid = as.character(patid),
         exposure = as.numeric(exposure))

### Save file

write.csv(treat_epi_all, episodes_csv_path, row.names = FALSE)

#####################################################################
### QUICK LOAD FROM HERE ###
#####################################################################

### Per protocol: keep only first coverage block (prioritizes first record in the case of multi-drug)

treat_epi_all <- read.csv(episodes_csv_path) %>%
  mutate(patid = as.character(patid),
         exposure = as.numeric(exposure),
         episode.start = as.Date(episode.start),
         episode.end = as.Date(episode.end)
  )

pp_epi <- treat_epi_all %>% group_by(patid) %>%
                             slice_min(episode.start, n = 1, with_ties = FALSE) %>%
                             ungroup() %>% mutate(patid = as.character(patid))

### Combine treatment episode info with base cohort

cohort <- read_sas(ps_final_sas_path)
cohort <- cohort %>% distinct(patid, .keep_all = TRUE)
fu_vars <- read_sas(base_cohort_sas_path, col_select = c(patid, censordate, aSAH_apc_dt, yob))
cohort <- left_join(cohort, fu_vars, by = "patid")

metformin_pp <- inner_join(pp_epi, cohort, by = "patid")

### Apply end of follow-up rules

metformin_pp <- metformin_pp %>%
  mutate(end_of_fu = lubridate::ymd(episode.end)) %>%
  mutate(end_of_fu = end_of_fu %>% replace_when(
    !is.na(censordate) & censordate < end_of_fu & censordate > lubridate::ymd(study_start_date) ~ censordate,
    !is.na(aSAH_apc_dt) & aSAH_apc_dt < end_of_fu & aSAH_apc_dt > lubridate::ymd(study_start_date) ~ aSAH_apc_dt,
    lubridate::ymd(study_end_date) < end_of_fu ~ lubridate::ymd(study_end_date)
  )) %>%
  mutate(aSAH = if_else(!is.na(aSAH_apc_dt) & aSAH_apc_dt <= end_of_fu, 1, 0)) %>%
  mutate(fu_days = ymd(end_of_fu) - ymd(episode.start))

write.csv(metformin_pp, perprotocol_csv_path, row.names = FALSE)
