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


data nl_tam_cleaning1;
set output.nl_drugs;
if duration < 1 then duration = quantity;
else if duration > 365 then duration = 28;
else duration = duration;
run;

proc sort data = bph_tam_cleaning1;
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
T.mean_daily_dose,
T.calc_dose,
BC.regstartdate
	FROM nl_tam_cleaning3 AS T
	LEFT OUTER JOIN output.nl_cohort AS BC ON BC.patid = T.patid /* key difference LEFT OUTER JOIN in place of INNER JOIN in NL cohort: includes non users of any medication */
ORDER BY T.patid, T.issuedate; 
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
		inner join nl_tam d2
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
		   d2.quantity,
		   d2.drugsubstancename
	from output.nl_cohort d1
		inner join nl_tam d2
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
		   p.drugsubstancename,
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
		   regstartdate,
		   drugsubstancename
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
