
/************************************************/
** 	the Treat-PRYSM project 					**
** 	by Sage Wyatt, Jos Kanning, & Shahab Abtahi **
** 	October 2025 - September 2026 				**
**	Drug - Tamsulosin							**
**												**
**	File 2.1: Cohort Creation for NL		**
/************************************************/;

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

/************************************************/
** 	the Treat-PRYSM project 					**
** 	by Sage Wyatt, Jos Kanning, & Shahab Abtahi **
** 	October 2025 - September 2026 				**
**	Drug - Tamsulosin							**
**												**
**	File 2.2: Exposure Generation for NL		**
/************************************************/;

/**************************************************************************/
/* Set up library references and global options                           */
/**************************************************************************/

libname rawdata "F:\Users\Wyatt003\BPH_nephrolithiasis\SAS";
libname output "F:\Users\Wyatt003\BPH_nephrolithiasis\Output";
libname codelist "F:\Users\Wyatt003\BPH_nephrolithiasis\Drug_Codelists";

options fullstimer; /* Display detailed resource usage info in log */



************************************** NEPHROLITHIASIS COHORT ****************************************;

%macro drugdata(in =, out=);


/**************************************************************************/
*** Step 1: Extract NL drug records;
/**************************************************************************/

*Improting analgesics codelist from ATC codes in ;
%macro product (var=, atccode =,drugfile=);
proc sql;
	CREATE TABLE codelist.&var._codes AS
	SELECT *
	FROM rawdata.product_aurum_atc 
	WHERE ATC LIKE &atccode;
quit;


proc sql;
	CREATE TABLE output.&var._drugs AS
	SELECT r.patid, 
		   r.issuedate, 
		   r.dosageid, 
		   r.quantity,
		   r.duration,
		   r.prodcodeid
	FROM &drugfile as r  
inner join codelist.&var._codes as c on strip(c.prodcodeid) = strip(r.prodcodeid);
quit;
%mend product;

%product (var=tamsulosin, atccode = 'G04CA%', drugfile = &in);

data output.nl_drugs;
set output.tamsulosin_drugs (in = a) output.analgesics_drugs (in = b);
if a then exposure = 1;
else if in b then exposure = 0;
run;


/* HOW MANY PATIENTS */
proc sql;
select count(distinct patid) as "Step 1: nl drugs"n
from output.nl_drugs
quit;


/****************************************************************************/
/* STEP 2: Join with base_cohort so only patients in our main cohort remain.*/
/****************************************************************************/


proc sort data = codelist.common_dosages;
by dosageid;
run;

proc sort data = output.nl_drugs;
by dosageid;
run;

data nl_dosages;
merge codelist.common_dosages (in=c) output.nl_drugs (in=d);
by dosageid;
if d;
run;

proc univariate data=nl_dosages;
	var daily_dose;
run;

proc univariate data=nl_dosages;
	var quantity;
run;


data nl_tam_cleaning;
set nl_dosages;
if daily_dose > 5 or daily_dose = . then daily_dose = 1;
if daily_dose = 0 then daily_dose = 0.5;
if quantity > 90 then quantity = 90;
if quantity > 0 and quantity ne . then assumed_duration = quantity/daily_dose;
if assumed_duration = . and duration ne . and duration > 0 and duration < 90 then assumed_duration = duration;
if assumed_duration = . or assumed_duration < 1 then assumed_duration = 30;
run; 

proc univariate data=nl_tam_cleaning;
	var assumed_duration;
run;


/* HOW MANY PATIENTS */
proc sql;
select count(distinct patid) as "Step 2: new variables"n
from nl_tam_cleaning
quit;

PROC SQL;
CREATE TABLE nl_tam AS
	SELECT  
T.issuedate, 
T.drugsubstancename, 
T.dosageid, 
T.quantity,
T.assumed_duration,
T.prodcodeid,
BC.regstartdate,
BC.patid,
BC.baseline_dt,
BC.censordate
	FROM output.nl_cohort AS BC 
	LEFT OUTER JOIN nl_tam_cleaning AS T ON BC.patid = T.patid; 
quit;


/* HOW MANY PATIENTS */
proc sql;
select count(distinct patid) as "Step 2: nltam join to base"n
from nl_tam
quit;

/**************************************************************************/
/* STEP 3: Exclude 'PrevalentUsers'                               */
/**************************************************************************/
/* 'Prevalent users' are those who had a drug prescription 1 year before   */
/* their baseline date. We identify them by comparing issue date with the  */
/* nl_dt in base_cohort. */
/* second step removes identified prevalent users from main dataset */


proc sql;
	create table PrevalentUsers as
	select distinct d1.patid
	from output.nl_cohort d1
		inner join nl_tam d2
		on d1.patid = d2.patid
	where d2.issuedate between intnx('year', d1.baseline_dt, -1, 'same') and d1.baseline_dt - 1;
quit;

/* HOW MANY PATIENTS */
proc sql;
select count(distinct patid) as "Step 3: prevalent user #"n
from PrevalentUsers
quit;


/* We remove those in PrevalentUsers.                                 */
/* We only keep prescriptions dated on or after baseline.             */

** lose patients here, but seems realistic;
** NOTE: this is running really slowly **;
proc sql;
	create table output.Rx_PostStart as
	select d1.*,
		   d2.issuedate,
		   d2.assumed_duration,
		   d2.prodcodeid,
		   d2.quantity,
		   d2.drugsubstancename
	from output.nl_cohort d1
		left outer join nl_tam d2
		on d1.patid = d2.patid
	where not exists (
		select 1
		from PrevalentUsers p
		where p.patid = d1.patid
		)
	;
quit;

/* HOW MANY PATIENTS */
proc sql;
select count(distinct patid) as "Step 3: removing prevalent users"n
from output.Rx_PostStart
quit;

proc freq data = output.Rx_PostStart;
tables drugsubstancename /MISSING;
run;

/**************************************************************************/
/* STEP 4: Identify earliest prescription date for each patient           */
/**************************************************************************/
/* Finds the minimum (earliest) eventdate among the valid prescriptions.  */

proc sql;
	create table output.NlEarliestDate as
	select patid,
		   min(issuedate) as earliest_rx_date format = ddmmyy10.
	from output.Rx_PostStart
	group by patid;
quit;


/* 1) We only keep rows where issuedate = earliest_rx_date.               */
/* 2) We call this 'EarliestRxAll'.                                       */
/* 3) We assign index_date                               */
proc sql;
	create table EarliestRxNlAll as
	select p.patid,
		   p.issuedate,
		   p.assumed_duration,
		   p.prodcodeid,
		   p.baseline_dt,
		   e.earliest_rx_date,
		   p.regstartdate,
		   p.drugsubstancename
	from output.Rx_PostStart as p
		inner join output.NlEarliestDate as e
		on p.patid = e.patid
	where p.issuedate = e.earliest_rx_date;
quit;

/*HOW MANY PATIENTS*/
* there are fewer observations here because it is grouped by patid rather than drugissue ;
proc sql;
select count(distinct patid) as "Step 4: First issue date"n
from EarliestRxNlAll
quit;

proc freq data = EarliestRxNlAll;
tables drugsubstancename /MISSING;
run;

/* excluding prescriptions not relevant to nl diagnosis, before or > 1 month later */


proc sql;
	create table EarliestRxNl_Filtered as
	select *
	from EarliestRxNlAll
	where earliest_rx_date - baseline_dt <= 30
	and earliest_rx_date >= baseline_dt;
quit;

/* TROUBLESHOOTING */
data test;
set EarliestRxNlAll;
daysdiff = earliest_rx_date - baseline_dt;
run;

proc sql;
select count(distinct patid) as "Step 4: drug for nl"n
from EarliestRxNl_Filtered 
quit;

proc freq data = EarliestRxNl_Filtered;
tables drugsubstancename /MISSING;
run;

/**************************************************************************/
/* STEP 7: Exclude if Follow-up period is less than 365 days  */
/**************************************************************************/

PROC SQL;
create table EarliestRx_washout AS
select * 
from EarliestRxNl_Filtered
having earliest_rx_date - regstartdate > 365;
quit;

/*HOW MANY PATIENTS*/
proc sql;
select count(distinct patid) as "Step 7: Washout exclusions"n
from EarliestRx_washout
quit;

proc freq data = EarliestRx_washout;
tables drugsubstancename /MISSING;
run;

**********;

/**************************************************************************/
/* STEP 8: Exclude if subarachnoid hemorrhage (aSAH) occurred before Rx  */
/**************************************************************************/

/* If a patient s first aSAH date (HOSP ONLY) is before earliest Rx, we drop them.    */
/* NOTE: DO NOT RUN UNTIL HES APC LINKAGE */
/* NOTE: Jos's version requires both hospital and gp data so I have written new script myself for the timebeing*/

*proc sql;
*CREATE TABLE EarliestRx_aSah_Exclusion AS
SELECT d1.* , d2.patid, d2.aSAH_gp_dt
FROM EarliestRx_washout as d1
INNER JOIN output.nl_cohort as d2 
ON d1.patid = d2.patid
	WHERE d2.aSAH_gp_dt > earliest_rx_date or d2.aSAH_gp_dt is NULL;
*quit;

/*HOW MANY PATIENTS*/
*proc sql;
*select count(distinct patid) as "Step 8: prior aSAH"n
from EarliestRx_aSah_Exclusion; 
*quit;

*proc freq data = EarliestRx_aSah_Exclusion;
*tables drugsubstancename /MISSING;
*run;


/**************************************************************************/
/* STEP 8: Link to ATC Codes  */
/**************************************************************************/

proc sql;
	create table &out as /* change to _2, _3, and _4 per file */
	select b.*, a.ATC
	from EarliestRx_washout b /* will replace after getting HES APC data to incorporate prior program*/
		left  outer join rawdata.product_aurum_atc as a
		on b.prodcodeid = a.prodcodeid;
quit;

proc sort data = &out;
by assumed_duration;
run;

%mend;


/**************************************************************************/
/* STEP 9: COMBINE FILES */
/**************************************************************************/

%drugdata(in=rawdata.drugissue_1, out= output.nldrugatc_1)

proc datasets library = work kill nolist;
run;
quit;

%drugdata(in=rawdata.drugissue_2, out= output.nldrugatc_2)

proc datasets library = work kill nolist;
run;
quit;

%drugdata(in=rawdata.drugissue_3, out= output.nldrugatc_3)

proc datasets library = work kill nolist;
run;
quit;

%drugdata(in=rawdata.drugissue_4, out= output.nldrugatc_4)

proc datasets library = work kill nolist;
run;
quit;


data output.all_nl_drugissue;
set output.nldrugatc_1
output.nldrugatc_2
output.nldrugatc_3
output.nldrugatc_4;
run;

/* HOW MANY PATIENTS */
proc sql;
select count(distinct patid) as "final product"n
from output.all_nl_drugissue
quit;

/**************************************************************************/
/* STEP 10: Extract patids of patients with linked HES data 			  */
/**************************************************************************/

proc sort data = output.all_nl_drugissue;
by patid issuedate;
run;

data bph_patients;
	set output.all_nl_drugissue;
	by patid issuedate;
	if first.patid then output;
	run;

proc sql;
	create table output.linked_nl_cohort as
	select a.* , b.linkyear, b.lsoa_e, b.hes_apc_e
	from nl_patients as a 
	inner join rawdata.aurum_eligibility_jan2026 as b on a.patid = b.patid
	where b.lsoa_e = 1 and b.hes_apc_e = 1;
quit;


*/ Is this analysis going to be possible ?/*;

data nl_patients;
	set output.all_nl_drugissue;
	by patid issuedate;
	if first.patid then output;
	run;

data test;
set nl_patients;
if aSAH_gp_dt = . then aSAH = 0;
if aSAH_gp_dt ne . then aSAH = 1;
if drugsubstancename ne "Tamsulosin" and drugsubstancename ne "Analgesic" then drugsubstancename = "None";
run;

proc freq data = test;
tables drugsubstancename * aSAH;
run;

*** ANOTHER WAY ***;

proc sql;
select count(distinct patid) as "nl_cohort"n
from output.nl_cohort;
quit;
