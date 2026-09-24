## the Treat-PRYSM project
## Drug - Metformin
##
## File 5_1: Per-protocol analysis driver - Cohort A (metformin vs. SU)
## Sets cohort parameters then source()s the shared body (5_0).

cohort_label <- "su"
comparator_name <- "Sulphonylureas"

perprotocol_csv_path <- "F:\\Users\\Wyatt003\\Metformin\\Output\\su_perprotocol.csv"

table1_docx_path         <- "F:\\Users\\Wyatt003\\Metformin\\Results\\metformin_su_pp_table1.docx"
matched_table1_docx_path <- "F:\\Users\\Wyatt003\\Metformin\\Results\\metformin_su_pp_matched_table1.docx"
cox_docx_path            <- "F:\\Users\\Wyatt003\\Metformin\\Results\\metformin_su_pp_cox.docx"
km_png_path              <- "F:\\Users\\Wyatt003\\Metformin\\Results\\metformin_su_km_graph.png"

source("F:\\Users\\Wyatt003\\Metformin\\VDI_Scripts\\5_0_METFORMIN_pp_body.R")
