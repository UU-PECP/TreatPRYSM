


libname rawdata "F:\Users\Wyatt003\BPH_nephrolithiasis\SAS";
libname output "F:\Users\Wyatt003\BPH_nephrolithiasis\Output";


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

		** 921729 patients ;

*STEP 2: Exclude patients from Wales and extract lcd; 
/*Import practice records */

proc sql;
	CREATE TABLE practice_1 AS
	SELECT
		region,
		lcd,
		pracid
	FROM rawdata.practice_1; 
quit;


proc sql;
	CREATE TABLE practice_2 AS
	SELECT
		region,
		lcd,
		pracid
	FROM rawdata.practice_2; 
quit;

proc sql;
	CREATE TABLE practice_3 AS
	SELECT
		region,
		lcd,
		pracid
	FROM rawdata.practice_3; 
quit;

proc sql;
	CREATE TABLE practice_4 AS
	SELECT
		region,
		lcd,
		pracid
	FROM rawdata.practice_4; 
quit;



data output.practice;
set practice_1
	practice_2
	practice_3
	practice_4;
run;

		** 1939 practices;

data test3;
set output.practice;
where region = 10;
run;


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
		** 1423855848 records; 

proc datasets library = work kill nolist;
run;
quit;



