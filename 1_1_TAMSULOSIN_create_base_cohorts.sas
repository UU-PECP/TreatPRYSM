
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
	CREATE TABLE output.rarediseasecases AS
	SELECT r.*
	FROM output.clinical as r
	inner join RareDisease_char as c on strip(c.newmedcodeid) = strip(r.medcodeid);
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

* STEP 7: Retrieve aSAH cases (GP-recorded, temporary until HES APC incorporated) *;

proc SQL;
	CREATE TABLE output.bph_cohort AS
	SELECT bc.*, 
		   aSAH.aSAH_dt as aSAH_gp_dt
	FROM output.BPH_initial AS bc
	LEFT OUTER JOIN output.aSAH_gp AS aSAH ON bc.patid = aSAH.patid;
quit;



proc SQL;
SELECT COUNT(*) FROM output.bph_cohort
WHERE aSAH_gp_dt IS NOT NULL;
quit;
		** 3433 aSAH cases in this cohort;

* STEP 8: Define baseline date and censor date *;

data output.bph_cohort;
	set output.bph_cohort;

	*Define baseline dt as the later of registration start date or bph_dt, floored at study start (31OCT2002);
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
set bph_genderexc (keep = patid yob regstartdate aSAH_gp_dt baseline_dt censordate reg_age);
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

proc freq data = output.linked_bph_cohort;
	tables linkyear;
run;
