## the Treat-PRYSM project
## Drug - Metformin
##
## File 5_2: Per-protocol analysis driver - Cohort B (metformin vs. SGLT2i)
## Sets cohort parameters then source()s the shared body (5_0).

cohort_label <- "sglt2i"
comparator_name <- "SGLT2 inhibitors"

perprotocol_csv_path <- "F:\\Users\\Wyatt003\\metformin\\Output\\sglt2i_perprotocol.csv"

table1_docx_path         <- "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Export\\metformin_sglt2i_pp_table1.docx"
matched_table1_docx_path <- "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Export\\metformin_sglt2i_pp_matched_table1.docx"
cox_docx_path            <- "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Export\\metformin_sglt2i_pp_cox.docx"
km_png_path              <- "C:\\Users\\Wyatt003\\OneDrive - Universiteit Utrecht\\Documents\\Export\\metformin_sglt2i_km_graph.png"

source("F:\\Users\\Wyatt003\\metformin\\VDI_Scripts\\5_0_METFORMIN_pp_body.R")
