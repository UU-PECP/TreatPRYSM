
/************************************************/
** 	the Treat-PRYSM project 					**
** 	Drug - Metformin							**
**												**
**	File 2_2: Cohort B driver - metformin vs.   **
**	SGLT2 inhibitors, 01 Jan 2014 - 31 Mar 2023 **
**	Sets cohort parameters then %includes the   **
**	shared exposure-generation body (2_0).      **
/************************************************/;

%let cohort_label = sglt2i;
%let startdate = '01JAN2014'd;
%let enddate = '31MAR2023'd;
%let comparator_file = F:\Users\Wyatt003\metformin\Codelists\flozins.txt;
%let comparator_name = SGLT2 inhibitors;

%include "F:\Users\Wyatt003\metformin\VDI_Scripts\2_0_METFORMIN_exposure_body.sas";
