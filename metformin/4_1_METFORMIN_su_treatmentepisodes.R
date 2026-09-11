## the Treat-PRYSM project
## Drug - Metformin
##
## File 4_1: Treatment episodes driver - Cohort A (metformin vs. SU)
## Sets cohort parameters then source()s the shared body (4_0).

cohort_label <- "su"

episodes_sas_path   <- "F:\\Users\\Wyatt003\\Metformin\\Output\\all_su_episodes.sas7bdat"
ps_final_sas_path    <- "F:\\Users\\Wyatt003\\Metformin\\Output\\su_ps_final.sas7bdat"
base_cohort_sas_path <- "F:\\Users\\Wyatt003\\Metformin\\Output\\t2dm_cohort.sas7bdat"

study_start_date <- "2004-01-01"
study_end_date   <- "2023-03-31"   ## overall database end, not the cohort's initiation window end -
                                     ## follow-up can extend past 2013-12-31 for patients who initiate late in the window
followup_window_years <- 20         ## covers index dates from 2004 through to the 2023-03-31 study end

episodes_csv_path    <- "F:\\Users\\Wyatt003\\Metformin\\Output\\su_treatmentepisodes.csv"
perprotocol_csv_path <- "F:\\Users\\Wyatt003\\Metformin\\Output\\su_perprotocol.csv"

source("F:\\Users\\Wyatt003\\Metformin\\VDI_Scripts\\4_0_METFORMIN_treatmentepisodes_body.R")
