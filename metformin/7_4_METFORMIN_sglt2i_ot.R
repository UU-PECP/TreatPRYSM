## the Treat-PRYSM project
## Drug - Metformin
##
## File 7_4: On-treatment analysis driver - Cohort B (metformin vs. SGLT2i)
## Sets cohort parameters then source()s the shared body (7_3_0).

cohort_label <- "sglt2i"
comparator_name <- "SGLT2 inhibitors"

ot_sas_path <- "F:\\Users\\Wyatt003\\Metformin\\Output\\sglt2i_ot_bmi_smk_age.sas7bdat"
study_start_date <- "2014-01-01"
results_dir <- "F:\\Users\\Wyatt003\\Metformin\\Results"

source("F:\\Users\\Wyatt003\\Metformin\\VDI_Scripts\\7_3_0_METFORMIN_ot_analysis_body.R")
