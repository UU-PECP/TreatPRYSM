
/************************************************/
** 	the Treat-PRYSM project 					**
** 	Drug - Metformin							**
**												**
**	File 2_1: Cohort A driver - metformin vs.   **
**	sulphonylureas, 01 Jan 2004 - 31 Dec 2013   **
**	Sets cohort parameters then %includes the   **
**	shared exposure-generation body (2_0).      **
/************************************************/;

%let cohort_label = su;
%let startdate = '01JAN2004'd;
%let enddate = '31DEC2013'd;
%let comparator_file = F:\Users\Wyatt003\Metformin\Drug_Codes\sulfonylureas.txt;
%let comparator_name = Sulphonylureas;

%include "F:\Users\Wyatt003\Metformin\VDI_Scripts\2_0_METFORMIN_exposure_body.sas";
