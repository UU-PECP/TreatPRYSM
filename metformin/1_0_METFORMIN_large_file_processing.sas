
/************************************************/
** 	the Treat-PRYSM project 					**
** 	Drug - Metformin							**
**												**
**	File 1_0: Raw extract processing            **
**	Reused unchanged in shape from                **
**	tamsulosin/1_0_large_file_processing.sas -   **
**	this step is entirely generic CPRD Aurum     **
**	ingestion (stringing together the 4-way      **
**	split patient/practice/observation extract   **
**	files, excluding Welsh practices), not       **
**	drug- or disease-specific. Metformin's raw   **
**	extract is its own pull (different patient   **
**	population - T2DM, not BPH/nephrolithiasis)  **
**	so this still needs to run once against it   **
**	before 1_1 can build the T2DM base cohort.   **
/************************************************/;

libname rawdata "F:\Users\Wyatt003\Metformin\Raw_Data";
libname output "F:\Users\Wyatt003\Metformin\Output";

*STEP 1: Define a base cohort by stringing together 4 patient files;
	*  	The following columns were not found in the contributing tables: crd, deathdate, frd, tod;
	* 	this is due to different variable names between CPRD Aurum and CPRD Gold;
	*	Equivalents in Aurum are regstartdate, cprd_ddate, regenddate;
proc sql;
	CREATE TABLE base_cohort_1 AS
	SELECT
		patid,
		gender,
		yob,
		regstartdate,
		cprd_ddate,
		regenddate,
		pracid
	FROM rawdata.patient_1;
quit;

proc sql;
	CREATE TABLE base_cohort_2 AS
	SELECT
		patid,
		gender,
		yob,
		regstartdate,
		cprd_ddate,
		regenddate,
		pracid
	FROM rawdata.patient_2;
quit;

proc sql;
	CREATE TABLE base_cohort_3 AS
	SELECT
		patid,
		gender,
		yob,
		regstartdate,
		cprd_ddate,
		regenddate,
		pracid
	FROM rawdata.patient_3;
quit;

proc sql;
	CREATE TABLE base_cohort_4 AS
	SELECT
		patid,
		gender,
		yob,
		regstartdate,
		cprd_ddate,
		regenddate,
		pracid
	FROM rawdata.patient_4;
quit;

data output.initial_cohort;
set base_cohort_1
	base_cohort_2
	base_cohort_3
	base_cohort_4;
run;

proc sql;
select count(distinct patid) as "Total extracted patients"n
from output.initial_cohort;
quit;

*STEP 2: Exclude patients from Wales and extract lcd;
/*Import practice records */

data output.practice;
set rawdata.practice_1
	rawdata.practice_2
	rawdata.practice_3
	rawdata.practice_4;
run;

proc sort data = output.practice nodupkey;
by pracid;
run;

proc sql;
select count(distinct pracid) as "Total practices"n
from output.practice;
quit;

proc sql;
CREATE TABLE output.initial_cohort AS
SELECT
		coh.patid,
		coh.gender,
		coh.yob,
		coh.regstartdate,
		coh.cprd_ddate,
		coh.regenddate,
		coh.pracid,
		pra.lcd
FROM output.initial_cohort AS coh
LEFT OUTER JOIN
		output.practice AS pra
		ON coh.pracid = pra.pracid
        WHERE pra.region ne 10; /* no Welsh practices in data, this step is technically unnecessary */
quit;

*STEP 3: Create 1 event file out of 4 event files;
	*	selecting only certain variables
	*	;

Data clinical_1 ;
Set rawdata.observation_1 (keep=patid obsdate medcodeid obstypeid);
run;

Data clinical_2 ;
Set rawdata.observation_2 (keep=patid obsdate medcodeid obstypeid);
run;

Data clinical_3 ;
Set rawdata.observation_3 (keep=patid obsdate medcodeid obstypeid);
run;

Data clinical_4 ;
Set rawdata.observation_4 (keep=patid obsdate medcodeid obstypeid);
run;

data output.clinical;
	set clinical_1
	clinical_2
	clinical_3
	clinical_4;
run;

proc datasets library = work kill nolist;
run;
quit;

proc sql;
create table unique_codes as
select distinct medcodeid
from output.clinical;
quit;
