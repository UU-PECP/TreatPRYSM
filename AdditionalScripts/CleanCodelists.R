### Loading packages ###

library(tidyverse)
library(readxl)
options(scipen = 999)

### Codelist generation by disease

    ### Fill in the following to generate a new file 
          #- OriginalFile. Path linking to original, raw file. Setup for .txt (read_delim), but with other file type can exchange read command for read.csv, read_xlsx, etc.
          #- LinkedIds. Input c("X" = "Y")... X =  available code variable in raw data, Y = equivalent in codebrowser data
          #- NewFilePath. Where would you like to save the clean file? What would you like it to be called?
          #- choose either CPRD gold or CPRD Aurum, both found in F: folder

      OriginalFilePath <- "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Codelists\\1_InitialCodes\\alcohol_abuse.txt"
      LinkedIds <- c("readcode" = "CleansedReadCode")
      NewFilePath <- "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Codelists\\2_CleanCodes\\alcohol.txt"
      Codebrowser <- read_delim("F:\\Research Information\\CPRD\\CPRD_CodeBrowser\\CPRD_CodeBrowser_Aurum\\CPRDAurumMedical.txt", delim = "\t")
      
    ### Stable Macro

      OriginalFile <- read_delim(OriginalFilePath, delim = "\t")
      #OriginalFile <- read.csv(OriginalFilePath)
      
      #OriginalFile <- OriginalFile %>% filter(str_detect(coding_system, "Read") == TRUE)
      
      LinkedToAurum <- inner_join(OriginalFile, Codebrowser, by = LinkedIds, keep = TRUE, suffix = c(".og", ""))
      
      CleanLinkedCodes <- LinkedToAurum %>% 
        select(MedCodeId, Observations, OriginalReadCode, Term) %>% 
        relocate(MedCodeId, Observations, OriginalReadCode, Term) %>%
        distinct(MedCodeId, .keep_all = TRUE)

        write.table(CleanLinkedCodes, NewFilePath, sep = "\t", row.names = FALSE)

        rm(CleanLinkedCodes, LinkedToAurum, OriginalFile)

