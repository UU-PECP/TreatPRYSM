
/************************************************/
** 	the Treat-PRYSM project 					**
** 	Drug - Metformin							**
**												**
**	File 7_1: On-treatment driver - Cohort A    **
**	(metformin vs. SU). Sets cohort parameters  **
**	then %includes the shared body (7_0).       **
/************************************************/;

%let cohort_label = su;
%let study_end = '31MAR2023'd;  /* overall database end, not the cohort's 2013 initiation-window end -
                                    follow-up continues past initiation until censoring/event/study end */
%let episodes_csv = F:\Users\Wyatt003\Metformin\Output\su_treatmentepisodes.csv;

%include "F:\Users\Wyatt003\Metformin\VDI_Scripts\7_0_METFORMIN_on_treatment_body.sas";
