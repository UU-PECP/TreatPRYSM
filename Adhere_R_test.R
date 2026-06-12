
library(tidyverse)

library(data.table)

install.packages("AdhereR")
library(AdhereR)


magdasubset<- as.data.table(magdasubset)

magdasubset[,atc:="abc"]







treat_episode <- compute.treatment.episodes(
  
  data = magdasubset,
  
  ID.colname = "patid",
  
  event.date.colname = "issuedate",
  
  event.duration.colname = "treatment_duration",
  
  medication.class.colname = "atc",
  
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

