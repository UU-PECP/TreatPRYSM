libname rawdata "F:\Users\Wyatt003\BPH_nephrolithiasis\SAS";
libname output "F:\Users\Wyatt003\BPH_nephrolithiasis\Output";
libname codelist "F:\Users\Wyatt003\BPH_nephrolithiasis\Codelists";

options fullstimer;



*STEP 1: Define a base cohort by stringing together 4 patient files;
	*  The following columns were not found in the contributing tables: crd, deathdate, frd, tod;
	* 	this is due to different variable names between CPRD Aurum and CPRD Gold;
	*	Equivalents in Aurum are regstartdate, cprd_ddate, regenddate;
proc sql;
	CREATE TABLE output.base_cohort_1 AS
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
	CREATE TABLE output.base_cohort_2 AS
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
	CREATE TABLE output.base_cohort_3 AS
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
	CREATE TABLE output.base_cohort_4 AS
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

*Combining files 1:4;

data output.initial_cohort;
set output.base_cohort_1
	output.base_cohort_2
	output.base_cohort_3
	output.base_cohort_4;
run;

*STEP 2: Create 1 event file out of 4 event files; 
Data output.clinical_1 ;
Set rawdata.observation_1 (keep=patid obsdate medcodeid obstypeid);
Where obstypeid > 7;
run;

Data output.clinical_2 ;
Set rawdata.observation_2 (keep=patid obsdate medcodeid obstypeid);
Where obstypeid > 7;
run;

Data output.clinical_3 ;
Set rawdata.observation_3 (keep=patid obsdate medcodeid obstypeid);
Where obstypeid > 7;
run;

Data output.clinical_4 ;
Set rawdata.observation_4 (keep=patid obsdate medcodeid obstypeid);
Where obstypeid > 7;
run;


*Combining files 1:4;

data output.clinical;
set output.clinical_1
	output.clinical_2
	output.clinical_3
	output.clinical_4;
run;

* STEP 3: Importing codelist;
		

proc import datafile = "C:\Users\Wyatt003\OneDrive - Universiteit Utrecht\Documents\Codelists\2_CleanCodes\bph.txt"
	out=codelist.bph_codelist
	dbms=dlm
	replace;
	delimiter='09'x;
	getnames=yes;
run;


* STEP 4: Checking;

proc contents data = codelist.bph_codelist;
run;
* patid is Numeric;

proc contents data = output.clinical;
run;
*patid is Character;

proc contents data = output.initial_cohort;
run;
*patid is Character;

proc print data=output.initial_cohort(obs=3);
run;


** Something is not right with step 5, because it says there are only 4000 patients with BPH;
		** This may be accurate and not an issue with excluding obsetypeid, because the unaltered first clinical file only has 1000 cases. Multiplied by 4 = 4000;
proc sql;
	CREATE TABLE test_cohort AS
	SELECT 
		cli1.patid, MIN(cli1.obsdate) AS bph_dt format=ddmmyy10.
	FROM 
		output.clinical_1 AS cli1
	INNER JOIN
		codelist.bph_codelist AS bph
		ON input(cli1.medcodeId, 8.) = bph.medcode
	GROUP BY cli1.patid;
quit;




* STEP 5: Get first bph date for each patient before end of study period;
* ;
proc sql;
	CREATE TABLE output.bph_cohort AS
	SELECT 
		cli.patid, MIN(cli.obsdate) AS bph_dt format=ddmmyy10.
	FROM 
		output.clinical AS cli
	INNER JOIN
		codelist.bph_codelist AS bph
		ON input(cli.medcodeId, 8.) = bph.medcode
	GROUP BY cli.patid;
quit;

*Add bph date to base cohort and define gender;
*X people without bph diagnosis;
PROC SQL;
	CREATE TABLE intermediatefile_1 AS
	SELECT
		bc.patid, 
		CASE WHEN bc.gender = "1" THEN "Male" WHEN bc.gender = "2" THEN "Female" END AS gender,
		bc.yob,
		bc.cprd_ddate,
		bc.regstartdate, 
		bc.cprd_ddate, 
		bc.regenddate,
		bph_coh.bph_dt
	FROM
		output.initial_cohort AS bc
	LEFT OUTER JOIN
		output.bph_cohort AS bph_coh
		ON input(bc.patid, 8.) = input(bph_coh.patid, 8.)
	WHERE bph_coh.bph_dt IS NOT NULL;
quit;

*Define baseline_dt;
*[CHECK WITH SHAHAB] For completeness this should include the start of HES APC coverage. However, since this is before our study period (April 1997), it is not necessary to add here.; 
data intermediatefile_2;
	set intermediatefile_1;

	*Define baseline dt as first date of 01-08-2004, uts, hypertension_dt, or crd;
	baseline_dt = max(of regstartdate bph_dt);
	if baseline_dt < '01JAN2004'd then baseline_dt = '01JAN2004'd;

	*Only include people w at least  365 days of continuous enrollment;
	days_diff = baseline_dt - regstartdate;
	if days_diff >= 365;

	*Drop variables no longer needed;
	drop days_diff regstartdate bph_dt;

	format baseline_dt ddmmyy10.;

run;

proc contents data = intermediatefile_2;
run;

*Only include individuals with both hospital inpatient (hes_apc_e) and socioeconomic status (lsao_e) data;
proc import datafile = "F:\Users\Wyatt003\Documentation CPRD\Aurum_enhanced_eligibility_November_2024.txt"
	out=output.linkage_coverage
	dbms=dlm
	replace;
	delimiter='09'x;
	getnames=yes;
run;

proc contents data = output.linkage_coverage;
run;


*Check how many people we lose here;
*Should be number of rows in utput.linkage_coverage;
*Check proportion of aSAH before and after;
proc sql;
	create table output.base_cohort as
	select bc.*
	from output.linkage_coverage as lc
	inner join intermediatefile_2 as bc on strip(put(lc.patid, 12.)) = bc.patid
	where lsoa_e = 1 and hes_apc_e = 1;
run;

proc contents data = output.base_cohort;
run;

*Quick sanity check to see whether there are no duplicates;
proc sql;
	create table test as
	select distinct patid
	from output.base_cohort;
run;

proc contents data = test;
run;
* no duplicates;

**** ADD LSOA and HES LINKAGE HERE WHEN AVAILABLE GIVEN CODE FROM JOS ***;

*Generate aSAH cases based on GP-codes as well for filter purposes;
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

proc SQL;
	CREATE TABLE output.base_cohort AS
	SELECT bc.*, 
		   aSAH.aSAH_dt as aSAH_gp_dt
	FROM output.base_cohort AS bc
	LEFT OUTER JOIN output.aSAH_gp AS aSAH ON bc.patid = aSAH.patid;
quit;

proc contents data = output.base_cohort;
run;


*No asah cases in the 824 bph patients!;


proc SQL;
SELECT COUNT(*) FROM output.base_cohort
WHERE aSAH_gp_dt IS NOT NULL;
quit;


