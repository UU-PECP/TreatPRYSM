
/********************************************/
** 	the Treat-PRYSM project 				**
** 	by Sage Wyatt and Shahab Abtahi 		**
** 	October 2025 - September 2026 			**
**	Drug - Tamsulosin						**
**											**
**	File 1.2: NL cohort selection and HES linkage **
/********************************************/;


libname rawdata "F:\Users\Wyatt003\BPH_nephrolithiasis\SAS";
libname output "F:\Users\Wyatt003\BPH_nephrolithiasis\Output";
libname codelist "F:\Users\Wyatt003\BPH_nephrolithiasis\3_MagdasCodes";
options fullstimer;


/**************************************************************************/
/* PREREQUISITES - built elsewhere, reused here (do NOT rebuild):         */
/*   output.clinical          (File 1_0)                                  */
/*   output.initial_cohort    (File 1_0)                                  */
/*   output.aSAH_gp           (File 1_1, Step 4)                          */
/*   output.rarediseasecases  (File 1_1)                                  */
/* Run File 1_0 and File 1_1 before this script.                          */
/**************************************************************************/


*******************************************************************************

********************* NEPHROLITHIASIS COHORT GENERATION ***********************

*******************************************************************************;

* STEP 5: Identify first nephrolithiasis diagnosis date for each patient before end of study period;

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

proc sort data = output.nl_cases;
by nl_dt;
run;

/* HOW MANY PATIENTS */
proc sql;
select count(distinct patid) as "Step 5: nl in clinical"n
from output.nl_cases;
quit;


* STEP 6: Restrict initial cohort to patients with a nephrolithiasis diagnosis;

PROC SQL;
	CREATE TABLE output.NL_initial AS
	SELECT
		bc.patid, 
		bc.gender,
		bc.yob,
		bc.lcd,
		bc.cprd_ddate,
		bc.regstartdate, 
		bc.regenddate,
		nl_coh.nl_dt
	FROM
		output.initial_cohort AS bc
	INNER JOIN
		output.nl_cases AS nl_coh
		ON bc.patid = nl_coh.patid;
quit;

/* HOW MANY PATIENTS */
proc sql;
select count(distinct patid) as "Step 6: nl in base cohort"n
from output.NL_initial;
quit;


* STEP 7: Retrieve aSAH cases (GP-recorded, temporary until HES APC incorporated) *;

proc SQL;
	CREATE TABLE output.nl_cohort AS
	SELECT bc.*, 
		   aSAH.aSAH_dt as aSAH_gp_dt
	FROM output.NL_initial AS bc
	LEFT OUTER JOIN output.aSAH_gp AS aSAH ON bc.patid = aSAH.patid;
quit;

proc SQL;
SELECT COUNT(*) as n_asah FROM output.nl_cohort
WHERE aSAH_gp_dt IS NOT NULL;
quit;


* STEP 8: Define baseline date and censor date *;

data output.nl_cohort;
	set output.nl_cohort;

	*Define baseline dt as registration start date, floored at NL study start (01DEC2007);
	informat baseline_dt DDMMYY10.;
	baseline_dt = regstartdate;
	if baseline_dt < '01DEC2007'd then baseline_dt = '01DEC2007'd;
	format baseline_dt DDMMYY10.;
	run;

data output.nl_cohort;
	set output.nl_cohort;
	studyend = '31MAR2025'd; 
	censordate = min(regenddate, cprd_ddate, lcd, studyend);
	format censordate ddmmyy10.;
	run;


* STEP 9: Exclude patients under 18 years old at baseline and rare diseases (e.g. Loeys-Dietz, Marfan syndrome);
*         NOTE: no sex restriction here - unlike BPH, nephrolithiasis occurs in both sexes;

data nl_ageexc;
set output.nl_cohort;
reg_age = year(baseline_dt) - yob;
if reg_age >= 18;
run;

/* HOW MANY PATIENTS */
proc sql;
select count(distinct patid) as "Step 9: no kids"n
from nl_ageexc;
quit;


proc sql;
	create table nl_rarediseaseexc as
	select *
	from nl_ageexc a
	where not exists (
		select 1 
		from output.rarediseasecases b
		where a.patid = b.patid
		);
quit;

/* HOW MANY PATIENTS */
proc sql;
select count(distinct patid) as "Step 9: no rare disease"n
from nl_rarediseaseexc;
quit;

/* sex distribution retained for reporting */
proc freq data = nl_rarediseaseexc;
tables gender;
run;


* STEP 10: *THE FINISHED PRODUCT* deduplication and HES linkage;

proc sort data = nl_rarediseaseexc;
by patid;
run;

data output.nl_cohort;
set nl_rarediseaseexc (keep = patid gender yob regstartdate nl_dt aSAH_gp_dt baseline_dt censordate reg_age);
by patid;
if first.patid;
run;

proc sort data = output.nl_cohort;
by patid;
run;

data unique_patients; /* Why 297942 rows in dataset but 297039 unique patients*/
set output.nl_cohort (keep = patid);
by patid;
if first.patid;
run;



proc sql;
	create table output.linked_nl_cohort as
	select a.* 
	from unique_patients as a 
	inner join rawdata.aurum_eligibility_jan2026 as b on a.patid = b.patid
	where b.lsoa_e = 1 and b.hes_apc_e = 1;
quit;

*** testing ***;

proc sql;
	select count(*) as total_rows,
	count(distinct patid) as unique_patients
	from output.linked_nl_cohort;
quit;
