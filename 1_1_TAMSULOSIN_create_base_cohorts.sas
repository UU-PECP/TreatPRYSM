
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
libname codelist "F:\Users\Wyatt003\BPH_nephrolithiasis\Codelists";
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

*Step 2; 
/* Exclude patients from wales*/
/* extract lcd */
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
        WHERE region ne 10;
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




*******************************************************************************

**************************** BPH COHORT GENERATION ****************************

*******************************************************************************;

* STEP 5: Add information on bph and baseline date;

	*Get first bph date for each patient before end of study period;
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
	LEFT OUTER JOIN
		output.bph_cases AS bph_coh
		ON bc.patid = bph_coh.patid
	WHERE bph_coh.bph_dt IS NOT NULL;
quit;



* STEP 6: Extract patids of patients with linked HES data;

* PROC SQL * ;

proc sql;
	create table output.linked_bph_cohort as
	select a.* , b.linkyear, b.lsoa_e, b.hes_apc_e
	from output.BPH_initial as a 
	left outer join rawdata.aurum_eligibility_jan2026 as b on a.patid = b.patid;
quit;

*check*;
proc freq data = output.linked_bph_cohort;
	tables hes_apc_e /MISSING;
	run;
*******;

proc sql;
create table output.exclude_bph_unlinked AS
select *
from output.linked_bph_cohort
where lsoa_e = 1 and hes_apc_e = 1;
quit;


* STEP 7: RETRIEVE aSAH CASES *;

proc SQL;
	CREATE TABLE output.bph_cohort AS
	SELECT bc.*, 
		   aSAH.aSAH_dt as aSAH_gp_dt
	FROM output.exclude_bph_unlinked AS bc
	LEFT OUTER JOIN output.aSAH_gp AS aSAH ON bc.patid = aSAH.patid;
quit;


* 3206 aSAH cases in this cohort;
proc SQL;
SELECT COUNT(*) FROM output.bph_cohort
WHERE aSAH_gp_dt IS NOT NULL;
quit;


* STEP 8: Add Baseline date *;

data output.bph_cohort;
	set output.bph_cohort;

	*Define baseline dt as first date of 01-08-2004, uts, hypertension_dt, or crd;
	baseline_dt = max(of regstartdate bph_dt);
	if baseline_dt < '31OCT2002'd then baseline_dt = '31OCT2002'd;
	run;

*******************************************************************************

********************** NEPHROLITHIASIS COHORT GENERATION **********************

*******************************************************************************;

*NOTE: contains several intermediate files in work library that will be overwritten later in nephrolithiasis cohort generation;
* STEP 9: Add information on bph and baseline date;

	*Get first nl date for each patient before end of study period;

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
	LEFT OUTER JOIN
		output.nl_cases AS nl_coh
		ON bc.patid = nl_coh.patid
	WHERE nl_coh.nl_dt IS NOT NULL;
	*without the above line, could this step be replaced by an inner join? ;
quit;


* STEP 10: Extract patids of patients with linked HES data;


proc sql;
	create table output.linked_nl_cohort as
	select bc.* , lc.linkyear, lc.lsoa_e, lc.hes_apc_e
	from output.nl_initial as bc 
	left outer join rawdata.aurum_eligibility_jan2026 as lc on bc.patid = lc.patid;
	
quit;

*check*;
proc freq data = output.linked_nl_cohort;
	tables hes_apc_e /MISSING;
	run;

*******;

proc sql;
create table output.exclude_nl_unlinked AS
select *
from output.linked_nl_cohort
where lsoa_e = 1 and hes_apc_e = 1;
quit;



* STEP 11: RETRIEVE aSAH CASES *;

proc SQL;
	CREATE TABLE output.nl_cohort AS
	SELECT bc.*, 
		   aSAH.aSAH_dt as aSAH_gp_dt
	FROM output.exclude_nl_unlinked AS bc
	LEFT OUTER JOIN output.aSAH_gp AS aSAH ON bc.patid = aSAH.patid;
quit;

proc contents data = output.nl_cohort;
run;

* 1084 aSAH cases in this cohort;
proc SQL;
SELECT COUNT(*) FROM output.nl_cohort
WHERE aSAH_gp_dt IS NOT NULL;
quit;

* STEP 12: Add Baseline date *;

data output.bph_cohort;
	set output.bph_cohort;

	*Define baseline dt as first date of 01-08-2004, uts, hypertension_dt, or crd;
	baseline_dt = max(of regstartdate nl_dt);
	if baseline_dt < '01DEC2007'd then baseline_dt = '01DEC2007'd;
	run;

***********************************************;
************** EXPORTING PATIDS ***************;
***********************************************;

* STEP 13: create external files;

* final count: 604422 patients;
proc export data = output.nl_cohort (keep = patid)
outfile = "C:\Users\Wyatt003\OneDrive - Universiteit Utrecht\Documents\Codelists\LinkedPatients_NL.csv"
dbms=csv
replace;
run;

*final count: 243789 patients;
proc export data = output.bph_cohort (keep = patid)
outfile = "C:\Users\Wyatt003\OneDrive - Universiteit Utrecht\Documents\Codelists\LinkedPatients_BPH.csv"
dbms=csv
replace;
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
	from linked_bph_cohort;
run;

proc contents data = test;
run;


