
/********************************************/
** 	the Treat-PRYSM project 				**
** 	by Sage Wyatt and Shahab Abtahi 		**
** 	October 2025 - September 2026 			**
**	Drug - Tamsulosin						**
**											**
**	File 1: Cohort selection and HES linkage**
/********************************************/;


libname rawdata "F:\Users\Wyatt003\BPH_nephrolithiasis\SAS";
libname output "F:\Users\Wyatt003\BPH_nephrolithiasis\Output";
libname codelist "F:\Users\Wyatt003\BPH_nephrolithiasis\3_MagdasCodes";
options fullstimer;



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
        WHERE pra.region ne 10; /* FIXED: was unqualified "region", now correctly references pra.region */
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


*Step 4: TEMPORARY find aSAH cases in clinical file;
	* replace with HES data when available;
proc sql;
	CREATE TABLE output.aSAH_gp AS
	SELECT 
		clin.patid, MIN(clin.obsdate) AS aSAH_dt format=ddmmyy10.
	FROM 
		output.clinical AS clin
	WHERE clin.medcodeId IN (
		"481028017", "300257016", "123511000006114", "123441000006112", "320735017",
		"123481000006118", "123521000006118", "123491000006115", "300244012",
		"300253017", "300935019", "300936018"
)
	GROUP BY clin.patid;
quit;


*Build rare disease codelist once, used by both BPH and NL cohorts below;

data RareDisease_cod;
	infile "F:\Users\Wyatt003\BPH_nephrolithiasis\3_MagdasCodes\RareDiseases.txt" dsd dlm='09'x firstobs=2 truncover;
	length medcodeid 8 ;
	input medcodeid :19. ;
run;

proc sql;
create table RareDisease_char as 
select put(medcodeid, 19.) as newmedcodeid
from RareDisease_cod;
quit;

proc sql;
	CREATE TABLE rarediseasecases AS
	SELECT r.*
	FROM output.clinical as r
	inner join RareDisease_char as c on strip(c.newmedcodeid) = strip(r.medcodeid);
quit;


*******************************************************************************

**************************** BPH COHORT GENERATION ****************************

*******************************************************************************;

* STEP 5: Identify first BPH diagnosis date for each patient before end of study period;

	*NOTE: generates 54 patients with missing bph dates not in initial cohort file;

proc sql;
	CREATE TABLE output.bph_cases AS
	SELECT 
		cli.patid, MIN(cli.obsdate) AS bph_dt format=ddmmyy10.
	FROM 
		output.clinical AS cli
	INNER JOIN
		codelist.bph AS bph
		ON cli.medcodeId = bph.medcode
        WHERE cli.obsdate < '31MAR2025'd
	GROUP BY cli.patid;
quit;



* STEP 6: Restrict initial cohort to patients with a BPH diagnosis;

PROC SQL;
	CREATE TABLE output.BPH_initial AS
	SELECT
		bc.patid, 
		bc.gender,
		bc.yob,
		bc.lcd,
		bc.cprd_ddate,
		bc.regstartdate, 
		bc.regenddate,
		bph_coh.bph_dt
	FROM
		output.initial_cohort AS bc
	INNER JOIN
		output.bph_cases AS bph_coh
		ON bc.patid = bph_coh.patid;
quit;


* STEP 7: Retrieve aSAH cases (GP-recorded, temporary until HES APC incorporated) *;

proc SQL;
	CREATE TABLE output.bph_cohort AS
	SELECT bc.*, 
		   aSAH.aSAH_dt as aSAH_gp_dt
	FROM output.BPH_initial AS bc
	LEFT OUTER JOIN output.aSAH_gp AS aSAH ON bc.patid = aSAH.patid;
quit;


* 3206 aSAH cases in this cohort;
proc SQL;
SELECT COUNT(*) FROM output.bph_cohort
WHERE aSAH_gp_dt IS NOT NULL;
quit;


* STEP 8: Define baseline date and censor date *;

data output.bph_cohort;
	set output.bph_cohort;

	*Define baseline dt as the later of registration start date or bph_dt, floored at study start (31OCT2002);
	informat baseline_dt DDMMYY10.;
	baseline_dt = max(of regstartdate bph_dt);
	if baseline_dt < '31OCT2002'd then baseline_dt = '31OCT2002'd;
	format baseline_dt DDMMYY10.;
	run;

data output.bph_cohort;
	set output.bph_cohort;
	studyend = '31MAR2025'd; 
	censordate = min(regenddate, cprd_ddate, lcd, studyend);
	format censordate ddmmyy10.;
	run;

* STEP 9: Exclude patients under 18 years old at baseline (aprox_age > 17 retains adults) *;

data output.bph_cohort;
set output.bph_cohort;
aprox_age = year(baseline_dt) - yob;
if aprox_age > 17;
run;

* STEP 10: Exclude rare disease cases (e.g. Loeys-Dietz, Marfan syndrome) *;

proc sql;
	create table bph_rarediseaseexc as
	select *
	from output.bph_cohort a
	where not exists (
		select 1 
		from rarediseasecases b
		where a.patid = b.patid
		);
quit;

*THE FINISHED PRODUCT*;

data output.bph_cohort;
set bph_rarediseaseexc (keep = patid yob regstartdate aSAH_gp_dt baseline_dt censordate);
run;



*******************************************************************************

********************** NEPHROLITHIASIS COHORT GENERATION **********************

*******************************************************************************;

*NOTE: contains several intermediate files in work library that will be overwritten later in nephrolithiasis cohort generation;
* STEP 11: Identify first nephrolithiasis diagnosis date for each patient before end of study period;

proc sql;
      CREATE TABLE output.nl_cases AS
      SELECT
          cli.patid, MIN(cli.obsdate) AS nl_dt format=ddmmyy10.
      FROM
          output.clinical AS cli
      INNER JOIN
          codelist.nephrolithiasis AS nl
          ON cli.medcodeId = nl.medcode
          WHERE cli.obsdate < '31MAR2025'd
      GROUP BY cli.patid;
quit;


* STEP 12: Restrict initial cohort to patients with a nephrolithiasis diagnosis;
	*Simplified from a LEFT OUTER JOIN + WHERE nl_dt IS NOT NULL to a plain INNER JOIN (equivalent result, clearer intent);

PROC SQL;
	CREATE TABLE NL_initial AS
	SELECT
		bc.patid,
		bc.yob,
		bc.cprd_ddate,
		bc.regstartdate, 
		bc.regenddate,
		bc.lcd,
		nl_coh.nl_dt
	FROM
		output.initial_cohort AS bc
	INNER JOIN
		output.nl_cases AS nl_coh
		ON bc.patid = nl_coh.patid;
quit;



* STEP 13: Retrieve aSAH cases (GP-recorded, temporary until HES APC incorporated) *;

proc SQL;
	CREATE TABLE output.nl_cohort AS
	SELECT bc.*, 
		   aSAH.aSAH_dt as aSAH_gp_dt
	FROM NL_initial AS bc
	LEFT OUTER JOIN output.aSAH_gp AS aSAH ON bc.patid = aSAH.patid;
quit;

proc contents data = output.nl_cohort;
run;

* 1084 aSAH cases in this cohort;
proc SQL;
SELECT COUNT(*) FROM output.nl_cohort
WHERE aSAH_gp_dt IS NOT NULL;
quit;

* STEP 14: Define baseline date and censor date *;

data output.nl_cohort;
	set output.nl_cohort;

	*Define baseline dt as the later of registration start date or nl_dt, floored at study start (01DEC2007);
	baseline_dt = max(of regstartdate nl_dt);
	if baseline_dt < '01DEC2007'd then baseline_dt = '01DEC2007'd;
	format baseline_dt DDMMYY10.;
	run;

data output.nl_cohort;
	set output.nl_cohort;
	studyend = '31MAR2025'd; 
	censordate = min(regenddate, cprd_ddate, lcd, studyend);
	format censordate ddmmyy10.;
	run;


* STEP 15: Exclude patients under 18 years old at baseline (aprox_age > 17 retains adults) *;

data nokids;
set output.nl_cohort;
aprox_age = year(baseline_dt) - yob;
if aprox_age > 17;
run;


* STEP 16: Exclude rare disease cases (e.g. Loeys-Dietz, Marfan syndrome) *;

/* Exclude 248 */
proc sql;
	create table nl_rarediseaseexc as
	select *
	from nokids a
	where not exists (
		select 1 
		from rarediseasecases b
		where a.patid = b.patid
		);
quit;


*THE FINISHED PRODUCT*;

data output.nl_cohort;
set nl_rarediseaseexc (keep = patid yob regstartdate nl_dt aSAH_gp_dt baseline_dt censordate);
run;

***********************************************;
**************** SANITY CHECKS ****************;
***********************************************;
proc SQL;
	CREATE TABLE asahonly AS
	SELECT bc.*
	FROM output.bph_cohort AS bc
	WHERE aSAH_gp_dt IS NOT NULL;
quit;


*where lsoa_e = 1 and hes_apc_e = 1;

Proc freq data = rawdata.linkage_eligibility ;
table hes_apc_e*lsoa_e ;
run;


	*Quick sanity check to see whether there are no duplicates;
	*No duplicates! ;
proc sql;
	create table test as
	select distinct patid
	from output.bph_cohort;
run;

proc contents data = test;
run;
