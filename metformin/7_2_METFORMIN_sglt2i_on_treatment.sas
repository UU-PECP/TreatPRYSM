
/************************************************/
** 	the Treat-PRYSM project 					**
** 	Drug - Metformin							**
**												**
**	File 7_2: On-treatment driver - Cohort B    **
**	(metformin vs. SGLT2i). Sets cohort         **
**	parameters then %includes the shared body   **
**	(7_0).                                       **
/************************************************/;

%let cohort_label = sglt2i;
%let study_end = '31MAR2023'd;
%let episodes_csv = F:\Users\Wyatt003\Metformin\Output\sglt2i_treatmentepisodes.csv;

%include "F:\Users\Wyatt003\Metformin\VDI_Scripts\7_0_METFORMIN_on_treatment_body.sas";
