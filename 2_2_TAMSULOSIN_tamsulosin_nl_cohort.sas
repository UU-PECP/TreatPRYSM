
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
libname codelist "F:\Users\Wyatt003\BPH_nephrolithiasis\Codelists";

options fullstimer; /* Display detailed resource usage info in log */



************************************** NEPHROLITHIASIS COHORT ****************************************;



%macro drugdata(in =, out=);

/**************************************************************************/
*** Step 1: Extract NL drug records;
/**************************************************************************/

proc sql;
	CREATE TABLE output.nl_drugs AS
	SELECT med.patid, 
		   med.issuedate, 
		   med.dosageid, 
		   med.quantity,
		   med.duration,
		   nlcod.drugsubstancename,
		   nlcod.ProdCodeId,
		   nlcod.mg_dose
	FROM 
		&in AS med /*Change to include all 4 files */
	INNER JOIN
		codelist.nl_drugs AS nlcod
		ON med.ProdCodeId = nlcod.ProdCodeId;
	quit;

/* HOW MANY PATIENTS */
proc sql;
select count(distinct patid) as "Step 1: nl drugs"n
from output.nl_drugs
quit;


/****************************************************************************/
/* STEP 2: Join with base_cohort so only patients in our main cohort remain.*/
/****************************************************************************/
/* calculates variable calc_dose as daily dose, which has strong correlation to daily_dose in 
common dosages file (see sanity check), though daily_dose in common dosages file
is not available for all records */
/* For records with duration < 7, assign 1 daily dose, and treatment duration equal to quantity */
/* For unusually high durations, assign median duration (28 days)*/

data nl_tam_cleaning1;
set output.nl_drugs;
if quantity < 1 AND duration < 7 then duration = 1;
else if quantity >= 1 AND duration < 7 then duration = quantity;
else if duration > 365 then duration = 30;
run;

proc sort data = nl_tam_cleaning1;
by duration;
run;

data nl_tam_cleaning2;
set nl_tam_cleaning1;
calc_dose = round(quantity / duration);
run;

data nl_tam_cleaning3;
set nl_tam_cleaning2;
if calc_dose = . then calc_dose = 1;
else if calc_dose < 1 then calc_dose = 0.5;
run;
		
data nl_tam_cleaning4;
set nl_tam_cleaning3;
mean_daily_dose = mg_dose * calc_dose;
run;	

/* HOW MANY PATIENTS */
proc sql;
select count(distinct patid) as "Step 2: new variables"n
from nl_tam_cleaning4
quit;

PROC SQL;
CREATE TABLE nl_tam AS
	SELECT  
T.issuedate, 
T.drugsubstancename, 
T.dosageid, 
T.quantity,
T.duration,
T.prodcodeid, 
T.mg_dose,
T.mean_daily_dose,
T.calc_dose,
BC.regstartdate,
BC.patid,
BC.nl_dt
	FROM output.nl_cohort AS BC 
	LEFT OUTER JOIN nl_tam_cleaning4 AS T ON BC.patid = T.patid; 
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
	where d2.issuedate between intnx('year', d1.baseline_dt, -1) and d1.baseline_dt - 1;
quit;

/* HOW MANY PATIENTS */
proc sql;
select count(distinct patid) as "Step 3: prevalent user #"n
from PrevalentUsers
quit;


/* We remove those in PrevalentUsers.                                 */
/* We only keep prescriptions dated on or after baseline.             */

** lose 30 thousand patients here, but seems realistic;
** NOTE: this is running really slowly **;
proc sql;
	create table output.Rx_PostStart as
	select d1.*,
		   d2.issuedate,
		   d2.duration,
		   d2.mean_daily_dose,
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


data rx_post_cleaning;
set output.Rx_PostStart;
druguse = 1;
if issuedate = . then druguse = 0;
if issuedate = . then issuedate = nl_dt;
run;


/* HOW MANY NON-TAMSULOSIN RECORDS */
proc freq data = rx_post_cleaning;
tables druguse /MISSING;
run;

/* HOW MANY PATIENTS */
proc sql;
select count(distinct patid) as "Step 3: issuedate > baseline"n
from rx_post_cleaning
quit;

proc freq data = rx_post_cleaning;
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
	from rx_post_cleaning
	group by patid;
quit;


/* 1) We only keep rows where issuedate = earliest_rx_date.               */
/* 2) We call this 'EarliestRxAll'.                                       */
/* 3) We assign index_date                               */
proc sql;
	create table output.EarliestRxNlAll as
	select p.patid,
		   p.issuedate,
		   p.duration,
		   p.prodcodeid,
		   p.nl_dt,
		   p.baseline_dt,
		   e.earliest_rx_date,
		   p.regstartdate,
		   p.drugsubstancename
	from rx_post_cleaning as p
		inner join output.NlEarliestDate as e
		on p.patid = e.patid
	where p.issuedate = e.earliest_rx_date;
quit;

/*HOW MANY PATIENTS*/
proc sql;
select count(distinct patid) as "Step 4: First issue date"n
from output.EarliestRxNlAll
quit;

proc freq data = output.EarliestRxNlAll;
tables drugsubstancename /MISSING;
run;

/* excluding prescriptions not relevant to nl diagnosis, before or > 1 month later */
*** Lost 20 thousand patients, significant but reasonable ***;

proc sql;
	create table EarliestRxNl_Filtered as
	select *
	from output.EarliestRxNlAll
	where earliest_rx_date - nl_dt <= 30
	and earliest_rx_date >= nl_dt;
quit;

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

proc sql;
CREATE TABLE EarliestRx_aSah_Exclusion AS
SELECT d1.* , d2.patid, d2.aSAH_gp_dt
FROM EarliestRx_washout as d1
INNER JOIN output.nl_cohort as d2 
ON d1.patid = d2.patid
	WHERE d2.aSAH_gp_dt > earliest_rx_date or d2.aSAH_gp_dt is NULL;
quit;

/*HOW MANY PATIENTS*/
proc sql;
select count(distinct patid) as "Step 8: prior aSAH"n
from EarliestRx_aSah_Exclusion; 
quit;

proc freq data = EarliestRx_aSah_Exclusion;
tables drugsubstancename /MISSING;
run;

/**************************************************************************/
/* STEP 9: Keep only the same drug as earliest for final prescription set */
/**************************************************************************/
/* 1) We bring back all prescriptions from Rx_PostStart that match the    */
/*    same exposure name and occur after earliest Rx date for that patid. */
/* 2) This will be used for bridging (continuous coverage) analysis.      */

proc sql;
	create table output.NlIndexDrug as
	select p.*
	from rx_post_cleaning p
		inner join EarliestRx_aSah_Exclusion e
		on p.patid = e.patid
	where p.drugsubstancename = e.drugsubstancename
	  and p.issuedate >= e.earliest_rx_date
	order by p.patid, p.issuedate;
quit;

/*HOW MANY PATIENTS*/
proc sql;
select count(distinct patid) as "Step 9: Rx b4 earliest"n
from output.NlIndexDrug 
quit;

*** Link to ATC codes ***;

proc sql;
	create table &out as /* change to _2, _3, and _4 per file */
	select b.*, a.ATC
	from output.NlIndexDrug b
		left  outer join rawdata.product_aurum_atc as a
		on b.prodcodeid = a.prodcodeid;
quit;

proc sort data = &out;
by duration;
run;

%mend;


/**************************************************************************/
/* STEP 10: COMBINE FILES */
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

/*HOW MANY PATIENTS*/
proc sql;
select count(distinct patid) as "total count"n
from output.all_nl_drugissue
quit;

proc sql;
select count(distinct patid) as "total count"n
from output.output.nldrugatc_4
quit;

proc sort data = output.all_nl_drugissue;
by duration patid issuedate;
run;

proc freq data = output.all_nl_drugissue;
tables drugsubstancename /MISSING;
run;

*/ Is this analysis going to be possible ?/*;

data test;
set output.all_nl_drugissue;
if aSAH_gp_dt = . then aSAH = 0;
if aSAH_gp_dt ne . then aSAH = 1;
if drugsubstancename ne "Tamsulosin" and drugsubstancename ne "Analgesic" then drugsubstancename = "None";
run;

proc freq data = test;
tables drugsubstancename * aSAH;
run;



