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

    ### Fill in the following to generate a new file 
          #- OriginalFile. Path linking to original, raw file. Setup for .txt (read_delim), but with other file type can exchange read command for read.csv, read_xlsx, etc.
          #- LinkedIds. Input c("X" = "Y")... X =  available code variable in raw data, Y = equivalent in codebrowser data
          #- NewFilePath. Where would you like to save the clean file? What would you like it to be called?
  

      OriginalFilePath <- "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Codelists\\1_InitialCodes\\chronic_kidney_disease.txt"
      LinkedIds <- c("readcode" = "CleansedReadCode")
      NewFilePath <- "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Codelists\\2_CleanCodes\\chronic_kidney_disease.txt"

    ### Stable Macro

      OriginalFile <- read_delim(OriginalFilePath, delim = "\t")
      #OriginalFile <- read.csv(OriginalFilePath)
      
      LinkedToAurum <- inner_join(OriginalFile, codebrowser, by = LinkedIds, keep = TRUE, suffix = c(".og", ""))
      
      CleanLinkedCodes <- LinkedToAurum %>% 
        select(MedCodeId, Observations, OriginalReadCode, Term) %>% 
        relocate(MedCodeId, Observations, OriginalReadCode, Term) %>% 
        rename_with(~NewVariables, 1:4) %>% 
        filter(!is.na(clinicalevents)) %>% 
        distinct(medcode, .keep_all = TRUE)

        write.table(CleanLinkedCodes, NewFilePath, sep = "\t", row.names = FALSE)

        rm(CleanLinkedCodes, LinkedToAurum, OriginalFile)

