
/********************************************/
** 	the Treat-PRYSM project 				**
** 	by Sage Wyatt and Shahab Abtahi 		**
** 	October 2025 - September 2026 			**
**	Drug - Tamsulosin						**
**											**
**	File 1: Cohort selection and HES linkage**
/********************************************/;


libname rawdata "F:\Users\Wyatt003\Tamsulosin\Raw_Data";
libname output "F:\Users\Wyatt003\Tamsulosin\Output";
libname codelist "F:\Users\Wyatt003\Tamsulosin\Disorder_Codes";
options fullstimer;



*Step 4: find GP aSAH cases in clinical file;
/* GP data
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
*/

/* HES Data */

data rawdata.hes_hosp;
	infile "F:\Users\Wyatt003\files\Type_2 25_006098\Type_2 25_006098\Aurum_linked\Final\hes_diagnosis_hosp_25_006098.txt" dsd dlm='09'x firstobs=2 truncover;
	length patid $19 spno $12 admidate 8 discharged 8 ICD $5 ICDx $1;
	input patid :$19. spno :$12. admidate :yymmdd10. discharged :yymmdd10. ICD :$5. ICDx :$1.;
	format admidate discharged date9.;
run;

proc sql;
	CREATE TABLE output.aSAH_apc AS
	SELECT 
		clin.patid, MIN(clin.admidate) AS aSAH_dt format=ddmmyy10., clin.ICD, clin.ICDx
	FROM 
		rawdata.hes_hosp AS clin
	WHERE clin.ICD IN (
		"I60", "I60.0", "I60.0", "I60.01", "I60.02",
		"I60.1", "I60.10", "I60.11", "I60.12",
		"I60.2", "I60.3", "I60.30", "I60.31", 
		"I60.32", "I60.4", "I60.5", "I60.50", 
		"I60.51", "I60.52", "I60.6", "I60.7", 
		"I60.8", "I60.9"
)
	GROUP BY clin.patid;
quit;

* testing *;

proc freq data = output.aSAH_apc;
	tables ICD / missing;
run;

proc freq data = output.aSAH_apc;
	tables ICDx / missing;
run;

	*Build rare disease codelist once, used by both BPH and NL cohorts below;


data RareDisease_cod;
	infile "F:\Users\Wyatt003\Tamsulosin\Disorder_Codes\RareDiseases.txt" dsd dlm='09'x firstobs=2 truncover;
	length medcodeid $19 ;
	input medcodeid :$19. ;
run;


proc sql;
	CREATE TABLE output.rarediseasecases AS
	SELECT r.*
	FROM output.clinical as r
	inner join RareDisease_cod as c on strip(c.medcodeid) = strip(r.medcodeid);
quit;

*** TESTING ***;
/*
data output.initial_cohort_TEST;
set rawdata.patient_2;
where input(patid, 19.) > 2000000000 and input(patid, 19.) < 3000000000;
run;

data output.clinical_TEST;
set rawdata.observation_2;
where input(patid, 19.) > 2000000000 and input(patid, 19.) < 3000000000;
run;
*/
*******************************************************************************

**************************** BPH COHORT GENERATION ****************************

*******************************************************************************;

* STEP 5: Identify first BPH diagnosis date for each patient before end of study period;

	*NOTE: generates 54 patients with missing bph dates;
	
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

proc sort data = output.bph_cases;
by bph_dt;
run;

/* HOW MANY PATIENTS */
proc sql;
select count(distinct patid) as "Step 5: bph in clinical"n
from output.bph_cases;
quit;
		**644621 patients;


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
		**644621 patients;

* STEP 7: Retrieve aSAH cases *;

proc SQL;
	CREATE TABLE output.bph_cohort AS
	SELECT bc.*, 
		   aSAH.aSAH_dt as aSAH_apc_dt
	FROM output.BPH_initial AS bc
	LEFT OUTER JOIN output.aSAH_apc AS aSAH ON bc.patid = aSAH.patid;
quit;



proc SQL;
SELECT COUNT(*) FROM output.bph_cohort
WHERE aSAH_apc_dt IS NOT NULL;
quit;
		** 3433 aSAH cases in GP data
		** 1117 aSAH cases in HES APC data ;

* STEP 8: Define baseline date and censor date *;

data output.bph_cohort;
	set output.bph_cohort;

	*Define baseline dt as registration start date, floored at study start (31OCT2002);
	informat baseline_dt DDMMYY10.;
	baseline_dt = regstartdate;
	if baseline_dt < '31OCT2002'd then baseline_dt = '31OCT2002'd;
	format baseline_dt DDMMYY10.;
	run;

data output.bph_cohort;
	set output.bph_cohort;
	studyend = '31MAR2025'd; 
	censordate = min(regenddate, cprd_ddate, lcd, studyend);
	format censordate ddmmyy10.;
	run;

* STEP 9: Exclude patients under 18 years old at baseline (reg_age > 17 retains adults), rare diseases (e.g. Loeys-Dietz, Marfan syndrome) , and non-males  *;

data bph_ageexc;
set output.bph_cohort;
reg_age = year(baseline_dt) - yob;
if reg_age >= 18;
run;


/* HOW MANY PATIENTS */
proc sql;
select count(distinct patid) as "Step 9: no kids"n
from bph_ageexc;
quit;
		**644348 patients;


proc sql;
	create table bph_rarediseaseexc as
	select *
	from bph_ageexc a
	where not exists (
		select 1 
		from output.rarediseasecases b
		where a.patid = b.patid
		);
quit;

/* HOW MANY PATIENTS */
proc sql;
select count(distinct patid) as "Step 9: no rare disease"n
from bph_rarediseaseexc;
quit;
		**644131 patients;

data bph_genderexc;
set bph_rarediseaseexc;
where gender = "1";
run;

/* HOW MANY PATIENTS */
proc sql;
select count(distinct patid) as "Step 9: males only"n
from bph_genderexc;
quit;
		**643930 patients;







* STEP 10: *THE FINISHED PRODUCT* and HES linkage;

proc sort data = bph_genderexc;
by patid;
run;

data output.bph_cohort;
set bph_genderexc (keep = patid yob regstartdate aSAH_apc_dt baseline_dt censordate reg_age);
by patid;
if first.patid;
run;

data unique_patients;
set output.bph_cohort (keep = patid);
by patid;
if first.patid;
run;

proc sql;
	create table output.linked_bph_cohort as
	select a.* 
	from unique_patients as a 
	inner join rawdata.aurum_eligibility_jan2026 as b on a.patid = b.patid
	where b.lsoa_e = 1 and b.hes_apc_e = 1;
quit;

*** testing ***;

proc sql;
	select count(*) as total_rows,
	count(distinct patid) as unique_patients
	from output.linked_bph_cohort;
quit;
	* 603842 patients;
