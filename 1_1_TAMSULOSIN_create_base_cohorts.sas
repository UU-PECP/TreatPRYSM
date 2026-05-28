libname rawdata "F:\Users\Wyatt003\BPH_nephrolithiasis\SAS";
libname output "F:\Users\Wyatt003\BPH_nephrolithiasis\Output";
libname codelist "C:\Users\Wyatt003\OneDrive - Universiteit Utrecht\Documents\Codelists\3_MagdasCodes";

options fullstimer;



*STEP 1: Define a base cohort by stringing together 4 patient files;
	*  The following columns were not found in the contributing tables: crd, deathdate, frd, tod;
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

*STEP 2: Combining base cohort files 1:4 to create initial_cohort, saved in output;

data output.initial_cohort;
set base_cohort_1
	base_cohort_2
	base_cohort_3
	base_cohort_4;
run;

*STEP 3: Create 1 event file out of 4 event files; 
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


*STEP 4: Combining base cohort files 1:4 to create initial_cohort, saved in output;

data output.clinical;
set clinical_1
	clinical_2
	clinical_3
	clinical_4;
run;


*STEP 5: Import HES linkage list to only include individuals with both hospital inpatient (hes_apc_e) and socioeconomic status (lsao_e) data;

proc import datafile = "F:\Users\Wyatt003\Documentation CPRD\Aurum_enhanced_eligibility_November_2024.txt"
	out=linkage_coverage
	dbms=dlm
	replace;
	delimiter='09'x;
	getnames=yes;
run;

* This is added upon reccommendation from Jos to actually add in trailing spaces to apc_linkage file patid;
proc sql;
create table linkage_character as
select lsoa_e, hes_apc_e,
put(patid, 19.) as patid length=19
from linkage_coverage; 
run;

*Step 6: TEMPORARY find aSAH cases in clinical file;
	* replace with HES data when available;
	* 4514 patients;
proc sql;
	CREATE TABLE output.aSAH_gp AS
	SELECT 
		clin.patid, MIN(clin.obsdate) AS aSAH_dt format=ddmmyy10.
	FROM 
		output.clinical AS clin
	WHERE clin.medcodeId IN (
		"481028017", "300257016", "80811100000611", "12351100000611", "12348100000611", "12352100000611", "12344100000611"
)
	GROUP BY clin.patid;
quit;



*******************************************************************************

**************************** BPH COHORT GENERATION ****************************

*******************************************************************************;

*NOTE: contains several intermediate files in work library that will be overwritten later in nephrolithiasis cohort generation;

* Something is not right with step 5, because it says there are only 4000 patients with BPH;
		* This may be accurate and not an issue with excluding obsetypeid, because the unaltered first clinical file only has 1000 cases. Multiplied by 4 = 4000;
		** update: after changing input 8. to input 19., there are now 3258 cases. Much lower than expected, but still higher.;
		*** update: fixed by Magda with Stat Transfer;
* STEP 5: Get first bph date for each patient before end of study period;
* I think this should be with the patients as the unit of analysis because of group by cli.patid, is this right? KALLIOPI;
proc sql;
	CREATE TABLE output.bph_patients AS
	SELECT 
		cli.patid, MIN(cli.obsdate) AS bph_dt format=ddmmyy10.
	FROM 
		output.clinical AS cli
	INNER JOIN
		codelist.bph AS bph
		ON cli.medcodeId = bph.medcode
	GROUP BY cli.patid;
quit;



* STEP 6: Add bph date to base cohort and define gender;
* KALLIOPI does the gender coding look logical to you? Do we need to define it?;
PROC SQL;
	CREATE TABLE intermediatefile_1 AS
	SELECT
		bc.patid, 
		bc.gender,
		bc.yob,
		bc.cprd_ddate,
		bc.regstartdate, 
		bc.cprd_ddate, 
		bc.regenddate,
		bph_coh.bph_dt
	FROM
		output.initial_cohort AS bc
	LEFT OUTER JOIN
		output.bph_patients AS bph_coh
		ON bc.patid = bph_coh.patid
	WHERE bph_coh.bph_dt IS NOT NULL;
quit;

*Step 7: Define baseline_dt;
*[CHECK WITH SHAHAB] For completeness this should include the start of HES APC coverage. However, since this is before our study period (April 1997), it is not necessary to add here.; 
data intermediatefile_2;
	set intermediatefile_1;

	*Define baseline dt as first date of 01-08-2004, uts, hypertension_dt, or crd;
	baseline_dt = max(of regstartdate bph_dt);
	if baseline_dt < '31OCT2002'd then baseline_dt = '31OCT2002'd;



	*Only include people w at least  365 days of continuous enrollment;
	days_diff = baseline_dt - regstartdate;
	if days_diff >= 365;

	*Drop variables no longer needed;
	drop days_diff regstartdate bph_dt;

	format baseline_dt ddmmyy10.;

run;

proc contents data = intermediatefile_2;
run;


*must strip both patids, otherwise outputs 0 observations;
* 340378 patients;
proc sql;
	create table linked_bph_cohort as
	select bc.*
	from linkage_character as lc
	inner join intermediatefile_2 as bc on strip(lc.patid) = strip(bc.patid)
	where lsoa_e = 1 and hes_apc_e = 1;
run;

proc contents data = linked_bph_cohort;
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

proc SQL;
	CREATE TABLE output.bph_cohort AS
	SELECT bc.*, 
		   aSAH.aSAH_dt as aSAH_gp_dt
	FROM linked_bph_cohort AS bc
	LEFT OUTER JOIN output.aSAH_gp AS aSAH ON bc.patid = aSAH.patid;
quit;

proc contents data = output.bph_cohort;
run;

* 1632 aSAH cases in this cohort;
proc SQL;
SELECT COUNT(*) FROM output.bph_cohort
WHERE aSAH_gp_dt IS NOT NULL;
quit;

*******************************************************************************

********************** NEPHROLITHIASIS COHORT GENERATION **********************

*******************************************************************************;

proc sql;
	CREATE TABLE output.nl_patients AS
	SELECT 
		cli.patid, MIN(cli.obsdate) AS nl_dt format=ddmmyy10.
	FROM 
		output.clinical AS cli
	INNER JOIN
		codelist.nephrolithiasis AS nl
		ON cli.medcodeId = nl.medcode
	GROUP BY cli.patid;
quit;

* STEP 6: Add nl date to base cohort and define gender;
* KALLIOPI does the gender coding look logical to you? Do we need to define it?;
* 1 is male 2 is female, we deleted character definitions because it seemed unecessary;

PROC SQL;
	CREATE TABLE intermediatefile_3 AS
	SELECT
		bc.patid,
		bc.yob,
		bc.cprd_ddate,
		bc.regstartdate, 
		bc.cprd_ddate, 
		bc.regenddate,
		nl_coh.nl_dt
	FROM
		output.initial_cohort AS bc
	LEFT OUTER JOIN
		output.nl_patients AS nl_coh
		ON bc.patid = nl_coh.patid
	WHERE nl_coh.nl_dt IS NOT NULL;
quit;

*Step 7: Define baseline_dt;
*[CHECK WITH SHAHAB] For completeness this should include the start of HES APC coverage. However, since this is before our study period (April 1997), it is not necessary to add here.; 
data intermediatefile_4;
	set intermediatefile_3;

	*Define baseline dt as first date of 01-08-2004, uts, hypertension_dt, or crd;
	*do we need this step?;
	baseline_dt = max(of regstartdate nl_dt);
	if baseline_dt < '1DEC2007'd then baseline_dt = '1DEC2007'd;



	*Only include people w at least  365 days of continuous enrollment;
	days_diff = baseline_dt - regstartdate;
	if days_diff >= 365;

	*Drop variables no longer needed;
	drop days_diff regstartdate nl_dt;

	format baseline_dt ddmmyy10.;

run;

proc contents data = intermediatefile_4;
run;

proc sql;
	create table linked_nl_cohort as
	select bc.*
	from linkage_character as lc
	inner join intermediatefile_4 as bc on strip(lc.patid) = strip(bc.patid)
	where lsoa_e = 1 and hes_apc_e = 1;
run;

* 141130 patients;

proc contents data = linked_nl_cohort;
run;

*Quick sanity check to see whether there are no duplicates;
*No duplicates! ;
proc sql;
	create table test as
	select distinct patid
	from linked_nl_cohort;
run;

proc contents data = test;
run;

proc SQL;
	CREATE TABLE output.nl_cohort AS
	SELECT bc.*, 
		   aSAH.aSAH_dt as aSAH_gp_dt
	FROM linked_nl_cohort AS bc
	LEFT OUTER JOIN output.aSAH_gp AS aSAH ON bc.patid = aSAH.patid;
quit;

proc contents data = output.nl_cohort;
run;

* 597 aSAH cases in this cohort;
proc SQL;
SELECT COUNT(*) FROM output.nl_cohort
WHERE aSAH_gp_dt IS NOT NULL;
quit;



***********************************************;
************** EXPORTING PATIDS ***************;
***********************************************;

proc export data = output.nl_cohort (keep = patid)
outfiles = "C:\Users\Wyatt003\OneDrive - Universiteit Utrecht\Documents\Codelists\LinkedPatients_NL.csv"
dbms=csv
replace;
run;

proc export data = output.bph_cohort (keep = patid)
outfiles = "C:\Users\Wyatt003\OneDrive - Universiteit Utrecht\Documents\Codelists\LinkedPatients_BPH.csv"
dbms=csv
replace;
run;
