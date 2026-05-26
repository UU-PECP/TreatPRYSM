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
run;

Data output.clinical_2 ;
Set rawdata.observation_2 (keep=patid obsdate medcodeid obstypeid);
run;

Data output.clinical_3 ;
Set rawdata.observation_3 (keep=patid obsdate medcodeid obstypeid);
run;

Data output.clinical_4 ;
Set rawdata.observation_4 (keep=patid obsdate medcodeid obstypeid);
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


** Something is not right with step 5, because it says there are only 4000 patients with BPH;
		** This may be accurate and not an issue with excluding obsetypeid, because the unaltered first clinical file only has 1000 cases. Multiplied by 4 = 4000;
		** update: after changing input 8. to input 19., there are now 3258 cases. Much lower than expected, but still higher.;

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
		ON input(cli.medcodeId, best19.) = bph.medcode
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


*/ lets try the other file;
			*** also not working, ran out of disk space somehow; 


/****** 	Check Raw Data Quality										 		 	*******/
**																						**								
** 		Project: Concomitant use of GCs and PPIs and Fx risk in RA patients - CPRD		**
**		Shahab Abtahi, Jan-Dec 2019 													**	
/******																				*******/;	

libname raw_data "F:\Users\Wyatt003\BPH_nephrolithiasis\SAS";
libname output "F:\Users\Wyatt003\BPH_nephrolithiasis\Output";
libname codelist "C:\Users\Wyatt003\OneDrive - Universiteit Utrecht\Documents\Codelists\3_MagdasCodes\tamsulosin_alfuzosin_finisteride.sas7bdat"

%let startstudy = MDY(1,1,2004);
%let endstudy = MDY(12,31,2026);



** Adding lcd & uts dates from Practice file ;

Data patient1;
set  raw_data.patient_1;
pracid = substr(patid,10);
run;

Data patient1;
set patient1;
pracid2 = substr(pracid,verify(pracid,'0'));
run;

Data patient1;
set patient1;
pracid3=pracid2*1;
drop pracid2 pracid;
rename pracid3 = pracid;
run;

Proc sort data = patient1;
by pracid;
run;


Data Patient;   * Losing 1,525 patients because they were dead or with tod before Start date, remaining: 31,844 
				Start is left censoring date, and End is right censring date
				lcd was added on 22.12.2019 - no change in eligible patient numbers happened at this stage ;
set Patient1;
	if cprd_ddate = . then cprd_ddate = 999999;
	if regenddate = . then regenddate = 999999;
	End = min (cprd_ddate, regenddate, &endstudy.);
	Start = max (regstartdate, &startstudy.);
	if End > Start;
	format Start ddmmyy10.;
	format End ddmmyy10.;
run;

*/ for testing */;

data sub1;
set RAW_DATA.observation_1;
where medcodeid = "396742015";
run;

data cleaned;
set practice;
if missing(medcodeid) then delete;
medcode = input(medcodeid, best19.);
run;

*/ testing done */;

/* trying magdas codes */

proc sql;
	CREATE TABLE output.magda_bph_cohort AS
	SELECT 
		cli.patid, MIN(cli.obsdate) AS bph_dt format=ddmmyy10.
	FROM 
		rawdata.observation_1 AS cli
	INNER JOIN
		codelist.bph AS bph
		ON cli.medcodeid = bph.medcode
	WHERE cli.obsdate <= MDY(3,31,2021)
	GROUP BY cli.patid;
quit;

/* it works! */


*/ what if we try initially usbsetting the data for all codes, because that worked */ ;

data sub1;
set RAW_DATA.observation_1;
where medcodeid = "19794011";
run;

data sub2;
set RAW_DATA.observation_1;
where medcodeid = "304382014";
run;

data sub3;
set RAW_DATA.observation_1;
where medcodeid = "304383016";
run;

data sub4;
set RAW_DATA.observation_1;
where medcodeid = "304384010";
run;

data sub5;
set RAW_DATA.observation_1;
where medcodeid = "304385011";
run;

data sub6;
set RAW_DATA.observation_1;
where medcodeid = "396738018";
run;

data sub7;
set RAW_DATA.observation_1;
where medcodeid = "396742015";
run;

data sub8;
set RAW_DATA.observation_1;
where medcodeid = "203421000006110";
run;

data sub9;
set RAW_DATA.observation_1;
where medcodeid = "645331000006112";
run;

data sub10;
set RAW_DATA.observation_1;
where medcodeid = "5493281000006110";
run;

data sub11;
set RAW_DATA.observation_1;
where medcodeid = "5493301000006114";
run;

data sub12;
set RAW_DATA.observation_1;
where medcodeid = "5493331000006118";
run;

data sub13;
set RAW_DATA.observation_1;
where medcodeid = "5493341000006111";
run;

data sub14;
set RAW_DATA.observation_1;
where medcodeid = "5493361000006110";
run;

data sub15;
set RAW_DATA.observation_1;
where medcodeid = "11851221000006114";
run;

data bph_obs;
set sub:;
run;

data output.bph_events;
set bph_obs;
keep medcode obsdate patid;
run;

Proc sort Data=patient;
by patid;
run;

Proc sort Data=output.bph_events;
by patid;
run;

Data bph_patients;
Set output.bph_events;
by patid;
if obsdate = . then delete;
run;

Proc sort data=bph_patients;
by patid obsdate;
run;

Data patientx;  *To hunt for just those RA read codes during valid data colelction,i.e. after Start ;
Merge patient (in=x) bph_patients (in=y);
	by patid;
	if x and y;
	if obsdate < Start then delete;
run;


*/ WE ARE HERE /;

Data patienty; 	
Set patientx;
	by patid;
	if first.patid;
	indexdate = obsdate;
	yob_new = yob + 1800;
	age = year(indexdate) - yob_new;
	if 118 >= age >= 50 and gender in (1,2) and (Start =< indexdate < End) and indexdate NE . ;
	sex = gender-1;
	format indexdate ddmmyy10.;
	yob = yob_new;
	Drop gender vmid yob_new mob chsreg chsdate capsup regstat reggap internal;
run;



/************ Paper Checks *************/

/* i.	How many patients have an end date on or after the index date? All patients (29,462) have End after index date. */

Data check1;
	set patienty (keep=patid indexdate end);
	if End > indexdate;
run;

Data check2;
	set patienty (keep=patid indexdate end);
	if End = indexdate;
run;

Data check3;
	set patienty (keep=patid indexdate end);
	if End < indexdate;
run;


/* ii.	How many patients are in your cohort? 29,462 */

Data check1;
set patienty;
run;


/* iii.	How many patients are older than 49 years? All of them, 29,462 */

Data check;
	set patienty (keep=patid age);
	if age > 49;
run;


/* iv.	How many patients are male, female, or have undefined gender? 9,085 men, 20,377 women, 0 undefind */

Data check1;
	set patienty (keep=patid sex);
	if sex = 0;
run;
Data check2;
	set patienty (keep=patid sex);
	if sex = 1;
run;
Data check3;
	set patienty (keep=patid sex);
	if sex > 1;
run;
 

/* v.	How many patients indeed have a first record for RA diagnosis on the index date? All of them, 29,462 */

Data check1;
Set patienty (keep=patid eventdate indexdate);
if eventdate = indexdate;
run;


/* vi.	Do you have any missing values for the patient ID/ index date/ date of birth/ gender? No! */

Data check1;
set patienty;
if patid = .;
run;

Data check2;
set patienty;
if indexdate = .;
run;

Data check3;
set patienty;
if yob = .;
run;

Data check4;
set patienty;
if sex = .;
run;


/* vii.	Do you have negative values for age at index date, or values are between 50 - 115? No negative values, yes all in range!  */

Proc univariate data=patienty;
	var age;
run;


/* viii.	Is the index date equal to or between the left and right censoring date? Yes for all 29,462 patients */

Data check;
	set patienty (keep=patid indexdate Start End);
	if Start =< indexdate =< End;
run;


/* ix.	External validity: is the age/gender distribution similar to the distribution of the general population? Yes,
			our gender ratio is 69.2% W/M which is similar to 73% in a RA study by Kim et al. Arth Res Ther 2010, or to 67.8% in a 
			CPRD study by Klop et al. Ann Rheum Dis 2016. Also the Age mean and median in our patients (70.4 and 70) is comparable
			to the latter article where it was 62.9 considering inclusion of 40-90 patients.  */

Data check1 new;
Set patienty (keep= patid age sex);
if sex = 0 then m + 1 ;
if sex = 1 then w + 1 ;
if _N_ = 29462 then sex_ratio = (w / (m + w));
if sex_ratio = . then output check1;
else if sex_ratio ~= . then output new;
run;

Proc univariate data=patienty;
	var age;
run;


/* x.	External validity: is the annual disease incidence similar to the general population? I checked incidene rates in random years
		during our sudy period, and we had 2063, 1873, 1020 and 527 new first RA cases during 2001, 20015, 2010, and 2015 respectively.
		Considering the active total population covered by CPRD as 4.425 milion in 2013 (Herrett et al. Int Jour Epid 2015), the 
		incidence rate will be around 11-35 per 100,000	which is comparable to Symmons, et al. Rheumat 1994. */

Data check1 check2 check3 check4;
Set patienty (keep= patid eventdate);
if year(eventdate) = 2001 then output check1;
if year(eventdate) = 2005 then output check2;
if year(eventdate) = 2010 then output check3;
if year(eventdate) = 2015 then output check4;
run;


/* xi:	Is indexdate after 1 January 1997? Yes, for all patients. */

Data check;
	set patienty;
	if indexdate >= &startstudy.;
run;



** Saving the final patient file ; 

Data wrk_data.Checked_patients;
Set patienty (Drop= medcode eventdate);
run;
* Patients number after quality checks: 29,462;

