## the Treat-PRYSM project
## Drug - Metformin
##
## File 4_2: Treatment episodes driver - Cohort B (metformin vs. SGLT2i)
## Sets cohort parameters then source()s the shared body (4_0).

cohort_label <- "sglt2i"

episodes_sas_path   <- "F:\\Users\\Wyatt003\\Metformin\\Output\\all_sglt2i_episodes.sas7bdat"
ps_final_sas_path    <- "F:\\Users\\Wyatt003\\Metformin\\Output\\sglt2i_ps_final.sas7bdat"
base_cohort_sas_path <- "F:\\Users\\Wyatt003\\Metformin\\Output\\t2dm_cohort.sas7bdat"

study_start_date <- "2014-01-01"
study_end_date   <- "2025-03-31"
followup_window_years <- 12

episodes_csv_path    <- "F:\\Users\\Wyatt003\\Metformin\\Output\\sglt2i_treatmentepisodes.csv"
perprotocol_csv_path <- "F:\\Users\\Wyatt003\\Metformin\\Output\\sglt2i_perprotocol.csv"

source("F:\\Users\\Wyatt003\\Metformin\\VDI_Scripts\\4_0_METFORMIN_treatmentepisodes_body.R")
