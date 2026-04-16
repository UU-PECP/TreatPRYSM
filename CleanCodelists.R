### Loading packages ###

library(tidyverse)
library(readxl)
options(scipen = 999)

### Importing Data ###

codebrowser <- read_delim("F:\\Research Information\\CPRD\\CPRD_CodeBrowser\\CPRD_CodeBrowser_Aurum\\CPRDAurumMedical.txt", delim = "\t")

headings <- read_delim("F:\\Users\\0631736\\New codelists\\anal_fissures.txt", delim = "\t") %>% slice(0) %>% select(medcode, clinicalevents, readcode, readterm)
NewVariables <- names(headings)
rm(headings)


### Codelist generation by disease

      ### For diabetes

      OriginalFile <- read_delim("C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Codelists\\1_InitialCodes\\diabetes_codelist.txt", delim = "\t")
  
      LinkedToAurum <- inner_join(OriginalFile, codebrowser, by = c("medcode" = "MedCodeId"), keep = TRUE, suffix = c(".og", ""))
  
      CleanLinkedCodes <- LinkedToAurum %>% 
        select(MedCodeId, Observations, OriginalReadCode, Term) %>% 
        relocate(MedCodeId, Observations, OriginalReadCode, Term) %>% 
        rename_with(~NewVariables, 1:4) %>% 
        filter(!is.na(clinicalevents)) %>% 
        distinct(medcode, .keep_all = TRUE)

        write.table(CleanLinkedCodes, "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Codelists\\2_CleanCodes\\diabetes.txt", sep = "\t", row.names = FALSE)

        rm(CleanLinkedCodes, LinkedToAurum, OriginalFile)


        ### For benign prostate hyperplasia
        
        OriginalFile <- read_delim("C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Codelists\\1_InitialCodes\\bph_codelist.txt", delim = "\t")
        
        LinkedToAurum <- inner_join(OriginalFile, codebrowser, by = c("medcode" = "SnomedCTConceptId"), keep = TRUE, suffix = c(".og", ""))
        
        CleanLinkedCodes <- LinkedToAurum %>% 
          select(MedCodeId, Observations, OriginalReadCode, Term) %>% 
          relocate(MedCodeId, Observations, OriginalReadCode, Term) %>% 
          rename_with(~NewVariables, 1:4) %>% 
          filter(!is.na(clinicalevents)) %>% 
          distinct(medcode, .keep_all = TRUE)
        
        write.table(CleanLinkedCodes, "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Codelists\\2_CleanCodes\\bph.txt", sep = "\t", row.names = FALSE)
        
        rm(CleanLinkedCodes, LinkedToAurum)

        
        ### For nephrolithiasis
        
        OriginalFile <- read_delim("C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Codelists\\1_InitialCodes\\nephrolithiasis_codelist.txt", delim = "\t")
        
        LinkedToAurum <- inner_join(OriginalFile, codebrowser, by = c("snowmedid" = "SnomedCTConceptId"), keep = TRUE, suffix = c(".og", ""))
        
        CleanLinkedCodes <- LinkedToAurum %>% 
          select(MedCodeId, Observations, OriginalReadCode, Term) %>% 
          relocate(MedCodeId, Observations, OriginalReadCode, Term) %>% 
          rename_with(~NewVariables, 1:4) %>% 
          filter(!is.na(clinicalevents)) %>% 
          distinct(medcode, .keep_all = TRUE)
        
        write.table(CleanLinkedCodes, "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Codelists\\2_CleanCodes\\nephrolithiasis.txt", sep = "\t", row.names = FALSE)
        
        rm(CleanLinkedCodes, LinkedToAurum)

