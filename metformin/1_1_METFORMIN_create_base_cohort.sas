
/************************************************/
** 	the Treat-PRYSM project 					**
** 	Drug - Metformin							**
**												**
**	File 1_1: T2DM base cohort + HES linkage	**
**	Modelled on tamsulosin/1_1 - shared by both **
**	the metformin-vs-SU and metformin-vs-SGLT2i **
**	cohorts (2_1 / 2_2 subset this further by   **
**	date window and drug exposure).             **
/************************************************/;

libname rawdata "F:\Users\Wyatt003\Metformin\Raw_Data";
libname output "F:\Users\Wyatt003\Metformin\Output";
libname codelist "F:\Users\Wyatt003\Metformin\Disorder_Codes";

options fullstimer;

/**************************************************************************/
/* STEP 1: aSAH cases from HES APC (identical ICD-10 I60.x list to        */
/* tamsulosin/1_1 - the outcome definition does not change between        */
/* studies)                                                                */
/*                                                                          */
/* PLACEHOLDER PATH: tamsulosin/1_1's HES APC infile path points to a      */
/* specific CPRD data-request folder ("Type_2 25_006098") that isn't a    */
/* metformin data request, so it was copied over here by mistake when     */
/* this file was built by mirroring tamsulosin/1_1's structure. Replace   */
/* with the actual path to metformin's own HES APC hospital diagnosis     */
/* extract once that data request exists.                                 */
/**************************************************************************/

data rawdata.hes_hosp;
	infile "F:\Users\Wyatt003\Metformin\Raw_Data\hes_diagnosis_hosp.txt" dsd dlm='09'x firstobs=2 truncover;
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
		"I60", "I60.0", "I60.00", "I60.01", "I60.02",
		"I60.1", "I60.10", "I60.11", "I60.12",
		"I60.2", "I60.3", "I60.30", "I60.31",
		"I60.32", "I60.4", "I60.5", "I60.50",
		"I60.51", "I60.52", "I60.6", "I60.7",
		"I60.8", "I60.9"
)
	GROUP BY clin.patid;
quit;

/**************************************************************************/
/* STEP 2: Rare disease exclusion codelist                                */
/* (autosomal dominant polycystic kidney disease, Ehlers-Danlos type IV,  */
/* Marfan, Loeys-Dietz, Majewski) - same exclusion list as tamsulosin,    */
/* these conditions are strongly associated with aSAH regardless of drug  */
/* exposure. NOTE: unlike the tamsulosin protocol's original version,     */
/* hypertension and diabetes are NOT part of this exclusion list, and     */
/* obviously can't be for metformin since T2DM defines the population.    */
/**************************************************************************/

data RareDisease_cod;
	infile "F:\Users\Wyatt003\Metformin\Disorder_Codes\RareDiseases.txt" dsd dlm='09'x firstobs=2 truncover;
	length medcodeid $19 ;
	input medcodeid :$19. ;
run;

proc sql;
	CREATE TABLE output.rarediseasecases AS
	SELECT r.*
	FROM output.clinical as r
	inner join RareDisease_cod as c on strip(c.medcodeid) = strip(r.medcodeid);
quit;

/**************************************************************************/
/* STEP 3: T2DM diagnosis codelist                                        */
/* (metformin/codelists/raw_cprd_browser_exports/diabetes_t2dm.txt,       */
/* imported here as codelist.t2dm)                                        */
/**************************************************************************/

data codelist.t2dm;
	infile "F:\Users\Wyatt003\Metformin\Disorder_Codes\diabetes_t2dm.txt" dsd dlm='09'x firstobs=2 truncover;
	length medcode $19 readcode $10 readterm $200;
	input medcode :$19. clinicalevents readcode :$10. readterm :$200.;
run;

/* STEP 4: Identify first T2DM diagnosis date for each patient before end of study period */
/* study period covers both cohorts: 01JAN2004 - 31MAR2023                */

proc sql;
	CREATE TABLE output.t2dm_cases AS
	SELECT
		cli.patid, MIN(cli.obsdate) AS t2dm_dt format=ddmmyy10.
	FROM
		output.clinical AS cli
	INNER JOIN
		codelist.t2dm AS t2dm
		ON cli.medcodeId = t2dm.medcode
    WHERE cli.obsdate < '31MAR2023'd
	GROUP BY cli.patid;
quit;

/* HOW MANY PATIENTS */
proc sql;
select count(distinct patid) as "Step 4: T2DM in clinical"n
from output.t2dm_cases;
quit;

/* STEP 5: Restrict initial cohort to patients with a T2DM diagnosis */

PROC SQL;
	CREATE TABLE output.T2DM_initial AS
	SELECT
		bc.patid,
		bc.gender,
		bc.yob,
		bc.lcd,
		bc.cprd_ddate,
		bc.regstartdate,
		bc.regenddate,
		t2dm_coh.t2dm_dt
	FROM
		output.initial_cohort AS bc
	INNER JOIN
		output.t2dm_cases AS t2dm_coh
		ON bc.patid = t2dm_coh.patid;
quit;

/* STEP 6: Retrieve aSAH cases */

proc SQL;
	CREATE TABLE output.t2dm_cohort AS
	SELECT bc.*,
		   aSAH.aSAH_dt as aSAH_apc_dt
	FROM output.T2DM_initial AS bc
	LEFT OUTER JOIN output.aSAH_apc AS aSAH ON bc.patid = aSAH.patid;
quit;

/* STEP 7: Define baseline date and censor date */
/* baseline_dt follows the same convention as tamsulosin/1_1: registration */
/* start date, floored at the overall study start (01JAN2004). This is    */
/* the washout anchor used by 2_1/2_2's "1 year enrolment before first    */
/* prescription" and prevalent-user checks - NOT the T2DM diagnosis date. */
/* t2dm_dt is kept on the cohort as a reference field only; the protocol  */
/* requires a T2DM diagnosis to exist in the record (the inner join in    */
/* Step 5 already enforces that) but does not require it to precede the   */
/* exposure/comparator index date by any specific margin.                 */

data output.t2dm_cohort;
	set output.t2dm_cohort;

	informat baseline_dt DDMMYY10.;
	baseline_dt = regstartdate;
	if baseline_dt < '01JAN2004'd then baseline_dt = '01JAN2004'd;
	format baseline_dt DDMMYY10.;
run;

data output.t2dm_cohort;
	set output.t2dm_cohort;
	studyend = '31MAR2023'd;
	censordate = min(regenddate, cprd_ddate, lcd, studyend);
	format censordate ddmmyy10.;
run;

/**************************************************************************/
/* STEP 8: Exclude patients under 18 years old at baseline, and rare      */
/* diseases. NOTE: unlike tamsulosin's BPH cohort, there is no sex        */
/* restriction here - both sexes are included in both metformin cohorts. */
/**************************************************************************/

data t2dm_ageexc;
set output.t2dm_cohort;
reg_age = year(baseline_dt) - yob;
if reg_age >= 18;
run;

/* HOW MANY PATIENTS */
proc sql;
select count(distinct patid) as "Step 8: no kids"n
from t2dm_ageexc;
quit;

proc sql;
	create table t2dm_rarediseaseexc as
	select *
	from t2dm_ageexc a
	where not exists (
		select 1
		from output.rarediseasecases b
		where a.patid = b.patid
		);
quit;

/* HOW MANY PATIENTS */
proc sql;
select count(distinct patid) as "Step 8: no rare disease"n
from t2dm_rarediseaseexc;
quit;

/**************************************************************************/
/* STEP 9: *THE FINISHED PRODUCT* and HES linkage                         */
/**************************************************************************/

proc sort data = t2dm_rarediseaseexc;
by patid;
run;

data output.t2dm_cohort;
set t2dm_rarediseaseexc (keep = patid gender yob regstartdate aSAH_apc_dt baseline_dt censordate reg_age t2dm_dt);
by patid;
if first.patid;
run;

data unique_patients;
set output.t2dm_cohort (keep = patid);
by patid;
if first.patid;
run;

proc sql;
	create table output.linked_t2dm_cohort as
	select a.*
	from unique_patients as a
	inner join rawdata.aurum_eligibility_jan2026 as b on a.patid = b.patid
	where b.lsoa_e = 1 and b.hes_apc_e = 1;
quit;

*** testing ***;

proc sql;
	select count(*) as total_rows,
	count(distinct patid) as unique_patients
	from output.linked_t2dm_cohort;
quit;
