
/************************************************/
** 	the Treat-PRYSM project 					**
** 	by Sage Wyatt, Jos Kanning, & Shahab Abtahi **
** 	October 2025 - September 2026 				**
**	Drug - Tamsulosin							**
**												**
**	File 2.1: Exposure Generation for BPH		**
/************************************************/;

/**************************************************************************/
/* Set up library references and global options                          */
/**************************************************************************/

libname rawdata "F:\Users\Wyatt003\BPH_nephrolithiasis\SAS";
libname output "F:\Users\Wyatt003\BPH_nephrolithiasis\Output";
libname codelist "F:\Users\Wyatt003\BPH_nephrolithiasis\Drug_Codelists";

options fullstimer; /* Display detailed resource usage info in log */


************************************** BPH COHORT ****************************************;
%macro drugdata(in =, out=);

/**************************************************************************/
/* STEP 1: Extract BPH drug records for the current drugissue file        */
/**************************************************************************/

%macro product (var=, atccode =, drugfile =); 
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
		   r.prodcodeid,
		   c.atc
	FROM &drugfile as r  
inner join codelist.&var._codes as c on strip(c.prodcodeid) = strip(r.prodcodeid);
quit;
%mend product;

%product (var=tamsulosin, atccode = 'G04CA%', drugfile = &in); 
%product (var=finisteride, atccode = 'G04CB%', drugfile = &in); 
%product (var=alfuzosin, atccode = 'G04CA01', drugfile = &in);


data output.bph_drugs;
set output.tamsulosin_drugs (in = a) output.finisteride_drugs (in = b) output.alfuzosin_drugs (in=c);
if a then exposure = 1;
else if b then exposure = 2;
else if c then exposure = 3;
run;


/* HOW MANY PATIENTS */
proc sql;
select count(distinct patid) as "Step 1: bph drugs"n
from output.bph_drugs
quit;


/****************************************************************************/
/* STEP 2: Generate treatment duration and mean daily dose in mg from common dosages file.*/
/****************************************************************************/

proc sort data = codelist.common_dosages;
by dosageid;
run;

proc sort data = output.bph_drugs;
by dosageid;
run;

data bph_dosages;
merge codelist.common_dosages (in=c) output.bph_drugs (in=d);
by dosageid;
if d;
run;

proc univariate data=bph_dosages;
	var daily_dose;
run;

proc univariate data=bph_dosages;
	var quantity;
run;

* borrowed from ADEPT script with permission from Magda *;

data bph_tam_cleaning;
set bph_dosages;
if daily_dose > 5 or daily_dose = . then daily_dose = 1;
if daily_dose = 0 then daily_dose = 0.5;
if quantity > 90 then quantity = 90;
if quantity > 0 and quantity ne . then assumed_duration = quantity/daily_dose;
if assumed_duration = . and duration ne . and duration > 0 and duration < 90 then assumed_duration = duration;
if assumed_duration = . or assumed_duration < 1 then assumed_duration = 30;
run; 

proc univariate data=bph_tam_cleaning;
	var assumed_duration;
run;



/****************************************************************************/
/* STEP 3: Join with base_cohort so only patients in our main cohort remain.*/
/****************************************************************************/

PROC SQL;
CREATE TABLE bph_tam AS
	SELECT T.patid, 
T.issuedate,  
T.exposure,
T.atc, 
T.dosageid, 
T.quantity,
T.assumed_duration,
T.prodcodeid,
BC.regstartdate
	FROM bph_tam_cleaning AS T
	INNER JOIN output.bph_cohort AS BC ON BC.patid = T.patid
ORDER BY T.assumed_duration, T.patid, T.issuedate; 
quit;



/* HOW MANY PATIENTS */
/* losing about 30 thousand*/
proc sql;
select count(distinct patid) as "Step 3: bphtam join to base"n
from bph_tam
quit;

/**************************************************************************/
/* STEP 4: Exclude 'PrevalentUsers'                                       */
/**************************************************************************/
/* 'Prevalent users' are those who had a drug prescription 1 year before   */
/* their baseline date. We identify them by comparing issue date with the  */
/* bph_dt in base_cohort. */
/* second step removes identified prevalent users from main dataset */


proc sql;
	create table PrevalentUsers as
	select distinct d1.patid
	from output.bph_cohort d1
		inner join bph_tam d2
		on d1.patid = d2.patid
	where d2.issuedate between intnx('year', d1.baseline_dt, -1, 'same') and d1.baseline_dt - 1;
	/* FIXED: added 'same' alignment so the lookback is a true 365-day window, consistent with the NL file,
	   rather than snapping to January 1st of the prior year */
quit;

/* HOW MANY PATIENTS */
proc sql;
select count(distinct patid) as "Step 4: prevalent user #"n
from PrevalentUsers
quit;


/* We remove those in PrevalentUsers.                                 */
/* We only keep prescriptions dated on or after baseline.             */

** lose 40 thousand patients here per file, but seems realistic;
** NOTE: this is running really slowly **;
proc sql;
	create table output.Rx_bph_PostStart as
	select d1.*,
		   d2.issuedate,
		   d2.assumed_duration,
		   d2.prodcodeid,
		   d2.quantity,
		   d2.exposure,
		   d2.atc
	from output.bph_cohort d1
		inner join bph_tam d2
		on d1.patid = d2.patid
	where not exists (
		select 1
		from PrevalentUsers p
		where p.patid = d1.patid
		)
	and d2.issuedate >= d1.baseline_dt
	;
quit;

/* HOW MANY PATIENTS */
proc sql;
select count(distinct patid) as "Step 4: removing prevalent users"n
from output.Rx_bph_PostStart
quit;

proc univariate data = output.Rx_bph_PostStart;
var assumed_duration;
run;

/**************************************************************************/
/* STEP 5: Identify earliest prescription date for each patient and exclude multi-drug initiators         */
/**************************************************************************/
/* Finds the minimum (earliest) eventdate among the valid prescriptions.  */

proc sql;
	create table output.BphEarliestDate as
	select patid,
		   min(issuedate) as earliest_rx_date format = ddmmyy10.
	from output.Rx_bph_PostStart
	group by patid;
quit;


/* 1) We only keep rows where issuedate = earliest_rx_date.               */
/* 2) We call this 'EarliestRxAll'.                                       */
/* 3) If multiple rows share the same earliest date for a patient, we     */
/*    handle that in the subsequent step.                                 */
/* why would we want to do this??? */
proc sql;
	create table output.EarliestRxBphAll as
	select p.patid,
		   p.issuedate,
		   p.assumed_duration,
		   p.prodcodeid,
		   p.baseline_dt,
		   e.earliest_rx_date,
		   p.regstartdate,
		   p.exposure,
		   p.atc
	from output.Rx_bph_PostStart as p
		left join output.BphEarliestDate as e
		on p.patid = e.patid
where p.issuedate = e.earliest_rx_date;
quit;


/*HOW MANY PATIENTS*/
proc sql;
select count(distinct patid) as "Step 5: First issue date"n
from output.EarliestRxBphAll
quit;
*** excluding multi-drug initiators;

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


/*HOW MANY PATIENTS*/
proc sql;
select count(distinct patid) as "Step 6: multi-drug"n
from EarliestRxBph_Filtered
quit;

proc sql;
	create table EarliestRxBph_Filtered as
	select distinct
	       patid, 
		   issuedate,
		   earliest_rx_date,
		   prodcodeid, 
		   assumed_duration,
		   baseline_dt,
		   exposure,
		   atc,
		   regstartdate
	from EarliestRxBph_Filtered
	group by patid, exposure
	having assumed_duration = max(assumed_duration)  /* Prefer longest treatment if two prescriptions on same date */
	;
quit;


/**************************************************************************/
/* STEP 6: Exclude if follow-up period is less than 365 days              */
/**************************************************************************/

PROC SQL;
create table EarliestRxBph_Filtered AS
select * 
from EarliestRxBph_Filtered
having earliest_rx_date - regstartdate > 365;
quit;

/*HOW MANY PATIENTS*/
proc sql;
select count(distinct patid) as "Step 7: Washout exclusions"n
from EarliestRxBph_Filtered
quit;

**********;
/*
/**************************************************************************/
/* STEP 7: Exclude if subarachnoid hemorrhage (aSAH) occurred before Rx   */
/* (COMMENTED OUT until HES APC linkage is incorporated )                      */
/**************************************************************************/
/* If a patient's first aSAH date (HOSP ONLY) is before earliest Rx, we drop them.    */
/* NOTE: DO NOT RUN UNTIL HES APC LINKAGE */
/* NOTE: Jos's version requires both hospital and gp data so I have written new script myself for the timebeing*/

*proc sql;
*CREATE TABLE EarliestRx_aSah_Exclusion AS
SELECT d1.* , d2.patid, d2.aSAH_gp_dt
FROM EarliestRx_washout as d1
INNER JOIN output.bph_cohort as d2 
ON d1.patid = d2.patid
	WHERE d2.aSAH_gp_dt > earliest_rx_date or d2.aSAH_gp_dt is NULL;
*quit;

/*HOW MANY PATIENTS*/
*proc sql;
*select count(distinct patid) as "Step 8: prior aSAH"n
from EarliestRx_aSah_Exclusion 
quit;


/**************************************************************************/
/* STEP 8: Retrieiving all treatment episodes from patients with exclusion criteria specified in steps 5 & 6   */
/**************************************************************************/

/* FINAL PRODUCT */

proc sql;
create table &out as
select r.*
from EarliestRxBph_Filtered as f
left outer join output.Rx_bph_PostStart as r
on f.patid = r.patid;
quit;

%mend;

/**************************************************************************/
/* STEP 9: Combine all four drugissue files                              */
/**************************************************************************/

* data subset test for shorter runtime;

data lildrugissue;
set rawdata.drugissue_1;
where input(patid, 19.) > 1000000000000 and input(patid, 19.) < 1050000000000;
run;

data lilpatient;
set rawdata.patient_1;
where input(patid, 19.) > 1000000000000 and input(patid, 19.) < 1050000000000;
run;

%drugdata(in=lildrugissue, out=output.bphdrugatc_test)

* real data input;

%drugdata(in=rawdata.drugissue_1, out=output.bphdrugatc_1)

proc datasets library = work kill nolist;
run;
quit;

%drugdata(in=rawdata.drugissue_2, out= output.bphdrugatc_2)

proc datasets library = work kill nolist;
run;
quit;

%drugdata(in=rawdata.drugissue_3, out= output.bphdrugatc_3)

proc datasets library = work kill nolist;
run;
quit;

%drugdata(in=rawdata.drugissue_4, out= output.bphdrugatc_4)

proc datasets library = work kill nolist;
run;
quit;


data output.all_bph_episodes;
set output.bphdrugatc_1
output.bphdrugatc_2
output.bphdrugatc_3
output.bphdrugatc_4;
run;

**************************
LC.mg_value * CASE 
							WHEN CD.daily_dose IS NULL THEN 1 
							WHEN CD.daily_dose = 0 THEN 0.5 
							ELSE CD.daily_dose 
						END AS mean_daily_dose
**************************;

/*HOW MANY PATIENTS? 264,340*/
proc sql;
select count(distinct patid) as "Final Product"n
from output.all_bph_episodes
quit;

/**************************************************************************/
/* STEP 10: Extract patids of patients with linked HES data               */
/**************************************************************************/
/* NOTE: currently collapses to first row per patient before linkage -    */
/* revisit whether this should retain full prescription history instead   */

proc sort data = output.all_bph_episodes;
by patid issuedate;
run;

/* Is this a valid way of collapsing the dataset? */
data bph_patients;
	set output.all_bph_episodes;
	by patid issuedate;
	if first.patid then output;
	run;

proc sql;
	create table output.linked_bph_cohort as
	select a.* 
	from bph_patients as a 
	inner join rawdata.aurum_eligibility_jan2026 as b on a.patid = b.patid
	where b.lsoa_e = 1 and b.hes_apc_e = 1;
quit;

/*HOW MANY PATIENTS? 252,596*/
proc sql;
select count(distinct patid) as "Linked patients"n
from output.linked_bph_cohort
quit;

***********************************************;
************** EXPORTING PATIDS ***************;
***********************************************;


*final count: 253 thousand patients;
proc export data = output.linked_bph_cohort (keep = patid)
outfile = "C:\Users\Wyatt003\OneDrive - Universiteit Utrecht\Documents\Codelists\LinkedPatients_BPH.csv"
dbms=csv
replace;
run;



/**************************************************************************/
/* STEP 12: Sanity testing - checks steps throughout BPH document         */
/**************************************************************************/


data bph_patients;
	set output.all_bph_episodes;
	by patid issuedate;
	if first.patid then output;
	run;

data test;
set bph_patients;
if aSAH_gp_dt = . then aSAH = 0;
if aSAH_gp_dt ne . then aSAH = 1;
run;

proc freq data = test;
tables exposure * aSAH;
run;

proc sort data = output.all_bph_drugissue;
by assumed_duration patid issuedate;
run;

*** how many records still have an odd duration?***;

data test;
set output.all_bph_drugissue;
if assumed_duration < 7 then oddvalues = "TRUE";
else if assumed_duration >= 7 then oddvalues = "FALSE";
run;

proc freq data = output.all_bph_drugissue;
tables oddvalues;
run; */ only 0.07*/;


data test;
set output.all_bph_drugissue;
if assumed_duration < 7 then assumed_duration = 30;
run;
