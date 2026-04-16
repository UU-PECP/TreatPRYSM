### Loading packages ###

library(tidyverse)
library(readxl)
options(scipen = 999)

### Importing Data ###

codebrowser <- read_delim("F:\\Research Information\\CPRD\\CPRD_CodeBrowser\\CPRD_CodeBrowser_Aurum\\CPRDAurumMedical.txt", delim = "\t")

headings <- read_delim("F:\\Users\\0631736\\New codelists\\anal_fissures.txt", delim = "\t") %>% slice(0) %>% select(medcode, clinicalevents, readcode, readterm)
NewVariables <- names(headings)
rm(headings)

diabetes <- read_delim("C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Scripts\\Codelists\\diabetes_codelist.txt", delim = "\t") 

### A somewhat standardized script that can be used for any codelist ###

disease <- diabetes

idtype <- "MedCodeId"

CodelistCleaner <- function(disease, idtype) {
  
  medcode <- variable.names(disease)[1]
  
  LinkedToAurum <- inner_join(disease, codebrowser, by = c("medcode" = idtype), keep = TRUE, suffix = c(".og", ""))
  
  CleanLinkedCodes <- LinkedToAurum %>% 
    select(MedCodeId, Observations, OriginalReadCode, Term) %>% 
    relocate(MedCodeId, Observations, OriginalReadCode, Term) %>% 
    rename_with(~NewVariables, 1:4) %>% 
    filter(!is.na(clinicalevents)) %>% 
    distinct(medcode, .keep_all = TRUE)
  
  disease <- CleanLinkedCodes
  
}

CodelistPrinter <- function(disease){
  
  output <- "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Scripts\\Codelists\\NAME.txt"
  
  NEWNAME <- deparse(substitute(disease))
  
  output <- str_replace(output, "NAME", NEWNAME)
  
  write.table(disease, output, sep = "\t", row.names = FALSE)

}







