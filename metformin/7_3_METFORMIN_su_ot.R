## the Treat-PRYSM project
## Drug - Metformin
##
## File 7_3: On-treatment analysis driver - Cohort A (metformin vs. SU)
## Sets cohort parameters then source()s the shared body (7_3_0).

cohort_label <- "su"
comparator_name <- "Sulphonylureas"

ot_sas_path <- "F:\\Users\\Wyatt003\\metformin\\Output\\su_ot_bmi_smk_age.sas7bdat"
study_start_date <- "2004-01-01"
results_dir <- "F:\\Users\\Wyatt003\\metformin\\Results"

source("F:\\Users\\Wyatt003\\metformin\\VDI_Scripts\\7_3_0_METFORMIN_ot_analysis_body.R")
