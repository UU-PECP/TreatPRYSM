
/************************************************/
** 	the Treat-PRYSM project 					**
** 	by Sage Wyatt, Jos Kanning, & Shahab Abtahi **
** 	October 2025 - September 2026 				**
**	Drug - Tamsulosin							**
**												**
**	File 2.1: Exposure Generation for BPH		**
/************************************************/;


/**************************************************************************/
/* Set up library references and global options                           */
/**************************************************************************/

libname rawdata "F:\Users\Wyatt003\BPH_nephrolithiasis\SAS";
libname output "F:\Users\Wyatt003\BPH_nephrolithiasis\Output";
libname codelist "C:\Users\Wyatt003\OneDrive - Universiteit Utrecht\Documents\Codelists\3_MagdasCodes";

options fullstimer; /* Display detailed resource usage info in log */

************************************** BPH COHORT ****************************************;

/**************************************************************************/
* Step 1: Extract BPH drug records;
/**************************************************************************/

	proc sql;
	CREATE TABLE output.bph_drugs AS
	SELECT med.patid, 
		   med.issuedate, 
		   med.dosageid, 
		   med.quantity,
		   med.duration,
		   bphcod.exposure,
		   bphcod.drugsubstancename,
		   bphcod.ProdCodeId,
		   bphcod.mg_dose
	FROM 
		rawdata.drugissue_1 AS med /*Change to include all 4 files */
	INNER JOIN
		codelist.bph_drugs_fixed AS bphcod
		ON med.ProdCodeId = bphcod.ProdCodeId;
quit;




/****************************************************************************/
/* STEP 2: Join with base_cohort so only patients in our main cohort remain.*/
/****************************************************************************/
/* calculates variable calc_dose as daily dose, which has strong correlation to daily_dose in 
common dosages file (see sanity check), though daily_dose in common dosages file
is not available for all records */
/* For records with duration < 7, assign 1 daily dose, and treatment duration equal to quantity */
/* For unusually high durations, assign median duration (28 days)*/

data bph_tam_cleaning1;
set output.bph_drugs;
if duration < 7 then duration = quantity;
else if duration > 365 then duration = 28;
else duration = duration;
run;

proc sort data = bph_tam_cleaning1;
by duration;
run;

data bph_tam_cleaning2;
set bph_tam_cleaning1;
calc_dose = round(quantity / duration);
run;

data bph_tam_cleaning3;
set bph_tam_cleaning2;
if calc_dose = . then calc_dose = 1;
else if calc_dose < 1 then calc_dose = 0.5;
run;
		
data bph_tam_cleaning4;
set bph_tam_cleaning3;
mean_daily_dose = mg_value * calc_dose;
run;	

PROC SQL;
CREATE TABLE bph_tam AS
	SELECT T.patid, 
T.issuedate, 
T.exposure, 
T.drugsubstancename, 
T.dosageid, 
T.quantity,
T.duration,
T.prodcodeid, 
T.mg_dose,
T.mean_daily_dose,
T.calc_dose,
BC.regstartdate
	FROM bph_tam_cleaning4 AS T
	INNER JOIN output.bph_cohort AS BC ON BC.patid = T.patid
ORDER BY T.duration, T.patid, T.issuedate; 
quit;


/**************************************************************************/
/* STEP 3: Exclude 'PrevalentUsers'                               */
/**************************************************************************/
/* 'Prevalent users' are those who had a drug prescription 1 year before   */
/* their baseline date. We identify them by comparing issue date with the  */
/* bph_dt in base_cohort. */
/* NOTE: using bph_dt instead of baseline_date on advice of patrick */
/* first step identifies prevalent users */
/* second step removes identified prevalent users from main dataset */


proc sql;
	create table PrevalentUsers as
	select distinct d1.patid
	from output.bph_cohort d1
		inner join bph_tam d2
		on d1.patid = d2.patid
	where d2.issuedate between intnx('year', d1.bph_dt, -1) and d1.bph_dt - 1;
quit;



/* We remove those in PrevalentUsers.                                 */
/* We only keep prescriptions dated on or after baseline.             */

proc sql;
	create table output.Rx_PostStart as
	select d1.*,
		   d2.issuedate,
		   d2.duration,
		   d2.mean_daily_dose,
		   d2.exposure,
		   d2.prodcodeid,
		   d2.quantity,
		   d2.drugsubstancename
	from output.bph_cohort d1
		inner join bph_tam d2
		on d1.patid = d2.patid
	where not exists (
		select 1
		from PrevalentUsers p
		where p.patid = d1.patid
		)
	and d2.issuedate >= d1.bph_dt
	;
quit;


/**************************************************************************/
/* STEP 4: Identify earliest prescription date for each patient           */
/**************************************************************************/
/* Finds the minimum (earliest) eventdate among the valid prescriptions.  */

proc sql;
	create table output.BphEarliestDate as
	select patid,
		   min(issuedate) as earliest_rx_date format = ddmmyy10.
	from output.Rx_PostStart
	group by patid;
quit;


/* 1) We only keep rows where issuedate = earliest_rx_date.               */
/* 2) We call this 'EarliestRxAll'.                                       */
/* 3) If multiple rows share the same earliest date for a patient, we     */
/*    handle that in the subsequent step.                                 */
proc sql;
	create table output.EarliestRxBphAll as
	select p.patid,
		   p.exposure,
		   p.issuedate,
		   p.duration,
		   p.prodcodeid,
		   p.bph_dt,
		   e.earliest_rx_date,
		   p.regstartdate,
		   p.drugsubstancename
	from output.Rx_PostStart as p
		inner join output.BphEarliestDate as e
		on p.patid = e.patid
	where p.issuedate = e.earliest_rx_date;
quit;


/**************************************************************************/
/* STEP 5: Exclude patients who have more than one record on earliest Rx  */
/**************************************************************************/
/* If a patient has > 1 row on the earliest date (possibly multiple drugs),*/
/* we remove them so each patient has exactly one earliest Rx.            */
proc sql;
	create table ExcludeMulti as
	select patid
	from output.EarliestRxBphAll
	group by patid
	having count(distinct exposure) > 1  /* More than 1 unique exposure => Exclude */
	;
quit;

proc sql;
	create table EarliestRxBph_Filtered as
	select *
	from output.EarliestRxBphAll
	where patid not in (select patid from output.ExcludeMulti);
quit;

proc sql;
	create table EarliestRxBph_Filtered as
	select distinct
	       patid, 
		   exposure, 
		   earliest_rx_date,
		   prodcodeid, 
		   duration,
		   bph_dt,
		   drugsubstancename,
		   regstartdate
	from EarliestRxBph_Filtered
	group by patid, exposure
	having duration = max(duration)  /* Prefer longest treatment if two prescriptions on same date */
	;
quit;

/**************************************************************************/
/* STEP 7: Exclude if Follow-up period is less than 365 days  */
/**************************************************************************/

** lose 30 thousand patients here, but durations seem realistic;

PROC SQL;
create table EarliestRx_washout AS
select * 
from EarliestRxBph_Filtered
having earliest_rx_date - regstartdate > 365;
quit;



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
INNER JOIN output.bph_cohort as d2 
ON d1.patid = d2.patid
	WHERE d2.aSAH_gp_dt > earliest_rx_date or d2.aSAH_gp_dt is NULL;
quit;


/**************************************************************************/
/* STEP 9: Keep only the same drug as earliest for final prescription set */
/**************************************************************************/
/* 1) We bring back all prescriptions from Rx_PostStart that match the    */
/*    same exposure name and occur after earliest Rx date for that patid. */
/* 2) This will be used for bridging (continuous coverage) analysis.      */

proc sql;
	create table output.BphIndexDrug as
	select p.*
	from output.Rx_PostStart p
		inner join EarliestRx_aSah_Exclusion e
		on p.patid = e.patid
	where p.exposure = e.exposure
	  and p.bph_dt >= e.earliest_rx_date
	order by p.patid, p.bph_dt;
quit;


*** Link to ATC codes ***;

proc sql;
	create table output.BphDrugAtc_1 as /* change to _2, _3, and _4 per file */
	select b.*, a.ATC
	from output.BphIndexDrug b
		left  outer join rawdata.product_aurum_atc as a
		on b.prodcodeid = a.prodcodeid;
quit;

proc sort data = output.BphDrugAtc_1;
by duration;
run;

*****SECOND FILE*****



/**************************************************************************/
/* STEP 10: SANITY TESTING */
/**************************************************************************/
/* Checks steps throughout BPH document      */


*check quantity *;

proc freq data = bph_tam;
	tables quantity / MISSING;
	run;

*****;

proc SQL;
SELECT COUNT(distinct patid) as n
FROM bph_tam;
quit;


** determining how to deal with daily dose outside of common_dosage file **;

proc sql;
create table test as
select BT.drugsubstancename, 
BT.dosageid, 
BT.quantity,
BT.duration,
CD.*, 
BT.quantity / BT.duration as calc_dose
from bph_tam as BT
left outer join codelist.common_dosages as CD
		on BT.dosageid = CD.dosageid;
quit;

proc means data = test mean n;
class daily_dose;
var calc_dose;
run;

*Based on these tests, quantity/duration is a good measure of daily dose;



/* Quick check: Count unique patients */
title "Numbers of unique ids in bph cohort";
proc sql;
  select count(distinct patid) as n_patid
  from bph_tam_dose;
quit;

/* Check that there are no negative or zero durations */
title "Numbers of people with 0 treatment duration";
proc sql;
  select count(*) as n_zero_treat
  from bph_tam_dose
  where treatment_duration <= 0;
quit;


/* Check the distribution of mean_daily_dose to see if it is plausible (no extremely large or negative values) */
/* Some extreme values (e.g. 5000). Need to correct for this later */
/* max is 30 */
title "Max mean_daily_dose";
proc sql;
  select max(mean_daily_dose)
  from bph_tam_dose;
quit;


proc contents data = bph_tam_dose;
run;


/* Check for ties in earliest date */
title "Number of multi drug initiators";
proc sql;
  select count(distinct patid) as n_excluded
  from ExcludeMulti;
quit;

/* replaced varaible d2.exposure with dr.prodcodeid, not sure if that is important;
/* Check how many unique patients remain after exclusion of prevalent. */
/* 185, 936 patients */
title "Numbers of unique ids after excluding prevalent users";
proc sql;
  select count(distinct patid) as n_patid
  from output.Rx_PostStart;
quit;

*checking*;

* though around a third of patients lost, durations look believable with most having 
* >365 days, and high frequency of first Rx on 0 days and 30 days;


PROC SQL;
create table EarliestRx_washout AS
select *, earliest_rx_date - regstartdate AS washout
from EarliestRxBph_Filtered;
quit;

proc sort data = EarliestRx_washout;
by duration;
run;

proc freq data = EarliestRx_washout;
tables duration;
run;

proc sort data = output.bph_drugs;
by duration patid issuedate;
run;

proc sql;
select median(duration) into :med_duration
from output.bph_drugs;
quit;

************************************** NEPHROLITHIASIS COHORT ****************************************;




/**************************************************************************/
* Step 1: Extract NL drug records;
/**************************************************************************/




proc sql;
	CREATE TABLE output.nl_drugs AS
	SELECT med.patid, 
		   med.issuedate, 
		   med.dosageid, 
		   med.quantity,
		   med.duration,
		   bphcod.exposure,
		   bphcod.drugsubstancename,
		   bphcod.ProdCodeId,
		   bphcod.mg_dose
	FROM 
		rawdata.drugissue_1 AS med /*Change to include all 4 files */
	INNER JOIN
		codelist.bph_drugs_fixed AS bphcod
		ON med.ProdCodeId = bphcod.ProdCodeId
	WHERE bphcod.drugsubstancename = "Tamsulosin"; /*key difference in NL cohort only including tamsulosin versus including comparator drugs */
quit;


/**************************************************************************/
/* STEP 2: Join with base_cohort so only patients in our main cohort remain.*/
/**************************************************************************/
/* calculates variable calc_dose as daily dose, which has strong correlation to daily_dose in 
common dosages file (see sanity check), though daily_dose in common dosages file
is not available for all records */

** START HERE** ;

PROC SQL;
CREATE TABLE nl_tam AS
	SELECT T.patid, 
T.issuedate, 
T.exposure, 
T.drugsubstancename, 
T.dosageid, 
T.quantity,
T.duration,
T.prodcodeid, 
T.mg_dose,
round(T.quantity / T.duration) as calc_dose,
BC.regstartdate
	FROM output.nl_drugs AS T
	LEFT OUTER JOIN output.nl_cohort AS BC ON BC.patid = T.patid /* key difference LEFT OUTER JOIN in place of INNER JOIN in NL cohort: includes non users of any medication */
ORDER BY T.patid, T.issuedate; 
quit;


/* calculate mean_daily_dose.*/


proc sql;
	create table nl_tam_dose as
	select * ,
		   mg_dose * CASE 
							WHEN calc_dose IS NULL THEN 1 
							WHEN calc_dose < 0 THEN 0.5 
							ELSE calc_dose 
						END AS mean_daily_dose
	from nl_tam
	ORDER BY patid, issuedate;
quit;


/**************************************************************************/
/* STEP 3: Exclude 'PrevalentUsers'                               */
/**************************************************************************/
/* 'Prevalent users' are those who had a drug prescription 1 year before   */
/* their baseline date. We identify them by comparing issue date with the  */
/* bph_dt in base_cohort. */
/* NOTE: using bph_dt instead of baseline_date on advice of patrick */
/* first step identifies prevalent users */
/* second step removes identified prevalent users from main dataset */


proc sql;
	create table PrevalentUsers as
	select distinct d1.patid
	from output.nl_cohort d1
		inner join nl_tam_dose d2
		on d1.patid = d2.patid
	where d2.issuedate between intnx('year', d1.nl_dt, -1) and d1.nl_dt - 1;
quit;



/* We remove those in PrevalentUsers.                                 */
/* We only keep prescriptions dated on or after baseline.             */

proc sql;
	create table output.Rx_PostStart as
	select d1.*,
		   d2.issuedate,
		   d2.duration,
		   d2.mean_daily_dose,
		   d2.exposure,
		   d2.prodcodeid,
		   d2.quantity
	from output.nl_cohort d1
		inner join nl_tam_dose d2
		on d1.patid = d2.patid
	where not exists (
		select 1
		from PrevalentUsers p
		where p.patid = d1.patid
		)
	and d2.issuedate >= d1.nl_dt
	;
quit;


/**************************************************************************/
/* STEP 4: Identify earliest prescription date for each patient           */
/**************************************************************************/
/* Finds the minimum (earliest) eventdate among the valid prescriptions.  */

proc sql;
	create table output.nlEarliestDate as
	select patid,
		   min(issuedate) as earliest_rx_date format = ddmmyy10.
	from output.Rx_PostStart
	group by patid;
quit;


/* 1) We only keep rows where issuedate = earliest_rx_date.               */
/* 2) We call this 'EarliestRxAll'.                                       */
/* 3) If multiple rows share the same earliest date for a patient, we     */
/*    handle that in the subsequent step.                                 */
proc sql;
	create table output.EarliestRxNlAll as
	select p.patid,
		   p.exposure,
		   p.issuedate,
		   p.duration,
		   p.prodcodeid,
		   p.nl_dt,
		   e.earliest_rx_date,
		   p.regstartdate
	from output.Rx_PostStart as p
		inner join output.nlEarliestDate as e
		on p.patid = e.patid
	where p.issuedate = e.earliest_rx_date;
quit;



proc sort data = output.nlEarliestDate;
by patid;
run;

proc sql;
create table test AS
select *
from output.Rx_PostStart 
	where patid not in(select patid from output.EarliestRxNlAll);
	quit;


/**************************************************************************/
/* STEP 5: Exclude patients who have more than one record on earliest Rx  */
/**************************************************************************/
/* If a patient has > 1 row on the earliest date (possibly multiple drugs),*/
/* we remove them so each patient has exactly one earliest Rx.            */
proc sql;
	create table ExcludeMulti as
	select patid
	from output.EarliestRxNlAll
	group by patid
	having count(distinct exposure) > 1  /* More than 1 unique exposure => Exclude */
	;
quit;

proc sql;
	create table EarliestRxNl_Filtered as
	select *
	from output.EarliestRxNlAll
	where patid not in (select patid from output.ExcludeMulti);
quit;

proc sql;
	create table EarliestRxNl_Filtered as
	select distinct
	       patid, 
		   exposure, 
		   earliest_rx_date,
		   prodcodeid, 
		   duration,
		   nl_dt,
		   regstartdate
	from EarliestRxNl_Filtered
	group by patid, exposure
	having duration = max(duration)  /* Prefer longest treatment if two prescriptions on same date */
	;
quit;

/**************************************************************************/
/* STEP 7: Exclude if Follow-up period is less than 365 days  */
/**************************************************************************/

** lose 30 thousand patients here, but durations seem realistic;

PROC SQL;
create table EarliestRx_washout AS
select * 
from EarliestRxNl_Filtered
having earliest_rx_date - regstartdate > 365;
quit;


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
INNER JOIN output.Nl_cohort as d2 
ON d1.patid = d2.patid
	WHERE d2.aSAH_gp_dt > earliest_rx_date or d2.aSAH_gp_dt is NULL;
quit;


/**************************************************************************/
/* STEP 9: Keep only the same drug as earliest for final prescription set */
/**************************************************************************/
/* 1) We bring back all prescriptions from Rx_PostStart that match the    */
/*    same exposure name and occur after earliest Rx date for that patid. */
/* 2) This will be used for bridging (continuous coverage) analysis.      */

proc sql;
	create table output.NlIndexDrug as
	select p.*
	from output.Rx_PostStart p
		inner join EarliestRx_aSah_Exclusion e
		on p.patid = e.patid
	where p.exposure = e.exposure
	  and p.nl_dt >= e.earliest_rx_date
	order by p.patid, p.nl_dt;
quit;


*** Link to ATC codes ***;

proc sql;
	create table output.nlDrugAtc_1 as /* change to _2, _3, and _4 per file */
	select *
	from output.NlIndexDrug b
		left outer join rawdata.atc_a10a as a
		on b.prodcodeid = a.prodcodeid;
quit;
