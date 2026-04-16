### Loading packages ###

library(tidyverse)
library(readxl)
options(scipen = 999)

### Importing Data ###

codebrowser <- read_delim("F:\\Research Information\\CPRD\\CPRD_CodeBrowser\\CPRD_CodeBrowser_Aurum\\CPRDAurumMedical.txt", delim = "\t")

paralysis <- read.csv("C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Scripts\\Codelists\\ParalysisCodes.csv")
  
menopause <- readxl::read_xlsx("C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Scripts\\Codelists\\MenopauseCodes.xlsx")

headings <- read_delim("F:\\Users\\0631736\\New codelists\\anal_fissures.txt", delim = "\t") %>% slice(0) %>% select(medcode, clinicalevents, readcode, readterm)


### Linking secondary codelists to CPRD Aurum ###

ParalysisSnomedID <- inner_join(paralysis, codebrowser, by = c("code" = "CleansedReadCode"))

MenopauseSnomedID <- inner_join(menopause, codebrowser, by = c("Concept Code" = "SnomedCTConceptId"))

### Sanity check... While there ar 54 codes in the original file, the joined file has 93 unique codes 
### This is because 18 concept IDs have more than 1 term and description AND 6 codes are not present in CPRD Aurum although they exist at large ###

MissingMenopauseCodes <- MenopauseSnomedID %>% filter(is.na(Observations))

MenopauseSnomedID %>% group_by(across(1:1)) %>% count() %>% filter(n > 1)

### Clean headings ###
### Deleting concepts with no equivalent in CPRD Aurum or Concept ID duplicates ###

### NOTE: does "clinical events" accurately represent "observations", or might "observations" also include referral, test, and immunization events? ###

NewVariables <- names(headings)

NewMenopauseSnomedID <- MenopauseSnomedID %>% 
  select(MedCodeId, Observations, OriginalReadCode, Term) %>% 
  relocate(MedCodeId, Observations, OriginalReadCode, Term) %>% 
  rename_with(~NewVariables, 1:4) %>% 
  filter(!is.na(clinicalevents)) %>% 
  distinct(medcode, .keep_all = TRUE)

NewParalysisSnomedID <- ParalysisSnomedID %>% 
  select(MedCodeId, Observations, OriginalReadCode, Term) %>% 
  relocate(MedCodeId, Observations, OriginalReadCode, Term) %>% 
  rename_with(~NewVariables, 1:4) %>% 
  filter(!is.na(clinicalevents)) %>% 
  distinct(medcode, .keep_all = TRUE)

### Outputting codelists ###

write.table(NewParalysisSnomedID, "paralysis.txt", sep = "\t")


write.table(NewMenopauseSnomedID, "menopause.txt", sep = "\t")




