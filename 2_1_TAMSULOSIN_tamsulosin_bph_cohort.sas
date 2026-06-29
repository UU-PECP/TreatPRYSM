
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
libname codelist "F:\Users\Wyatt003\BPH_nephrolithiasis\Drug_Codelists";

options fullstimer; /* Display detailed resource usage info in log */

************************************** BPH COHORT ****************************************;
%macro drugdata(in =, out=);

/**************************************************************************/
*** Step 1: Extract BPH drug records;
/**************************************************************************/


%macro product (var=, code=);
data &var._cod;
	infile "F:\Users\Wyatt003\BPH_nephrolithiasis\Drug_Codelists\&code..txt" dsd dlm='09'x firstobs=2 truncover;
	length prodcodeid 8 DMDCode 8 TermfromEMIS $36 ProductName $36 drugsubstancename $36.;
	input prodcodeid :19. DMDCode :19. TermfromEMIS :$36. ProductName :$36. drugsubstancename :$36.;
run;

proc sql;
create table &var._char as 
select prodcodeid, drugsubstancename, put(prodcodeid, 19.) as newprodcodeid
from &var._cod;
quit;


proc sql;
	CREATE TABLE output.&var._drugs AS
	SELECT r.patid, 
		   r.issuedate, 
		   r.dosageid, 
		   r.quantity,
		   r.duration,
		   c.drugsubstancename,
		   c.ProdCodeId
	FROM rawdata.drugissue_1 as r
inner join &var._char as c on strip(c.newprodcodeid) = strip(r.prodcodeid);
quit;

%mend product;

%product (var=bph, code=bph);


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

data output.bph_tam_cleaning;
set bph_dosages;
if daily_dose > 5 or daily_dose = . then daily_dose = 1;
if daily_dose = 0 then daily_dose = 0.5;
if quantity > 90 then quantity = 90;
if quantity > 0 and quantity ne . then assumed_duration = quantity/daily_dose;
if assumed_duration = . and duration ne . and duration > 0 and duration < 90 then assumed_duration = duration;
if assumed_duration = . or assumed_duration < 1 then assumed_duration = 30;
run; 

proc univariate data=output.bph_tam_cleaning;
	var assumed_duration;
run;



/****************************************************************************/
/* STEP 3: Join with base_cohort so only patients in our main cohort remain.*/
/****************************************************************************/

PROC SQL;
CREATE TABLE bph_tam AS
	SELECT T.patid, 
T.issuedate,  
T.drugsubstancename, 
T.dosageid, 
T.quantity,
T.duration,
T.prodcodeid, 
T.mg_dose,
T.mean_daily_dose,
BC.regstartdate
	FROM bph_tam_cleaning AS T
	INNER JOIN output.bph_cohort AS BC ON BC.patid = T.patid
ORDER BY T.duration, T.patid, T.issuedate; 
quit;



/* HOW MANY PATIENTS */
/* losing about 30 thousand*/
proc sql;
select count(distinct patid) as "Step 2: bphtam join to base"n
from bph_tam
quit;

/**************************************************************************/
/* STEP 3: Exclude 'PrevalentUsers'                               */
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
	where d2.issuedate between intnx('year', d1.baseline_dt, -1) and d1.baseline_dt - 1;
quit;

data test;
set output.Rx_PostStart;
usedate = intnx('year', baseline_dt, -1, 'same');
format usedate ddmmyy10.;
format baseline_dt ddmmyy10.;
run;

/* HOW MANY PATIENTS */
proc sql;
select count(distinct patid) as "Step 3: prevalent user #"n
from PrevalentUsers
quit;


/* We remove those in PrevalentUsers.                                 */
/* We only keep prescriptions dated on or after baseline.             */

** lose 30 thousand patients here per file, but seems realistic;
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
select count(distinct patid) as "Step 3: removing prevalent users"n
from output.Rx_PostStart
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
		   p.issuedate,
		   p.duration,
		   p.prodcodeid,
		   p.bph_dt,
		   p.baseline_dt,
		   e.earliest_rx_date,
		   p.regstartdate,
		   p.drugsubstancename
	from output.Rx_PostStart as p
		inner join output.BphEarliestDate as e
		on p.patid = e.patid
	where p.issuedate = e.earliest_rx_date;
quit;


/*HOW MANY PATIENTS*/
proc sql;
select count(distinct patid) as "Step 4: First issue date"n
from output.EarliestRxBphAll
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
	having count(distinct drugsubstancename) > 1  /* More than 1 unique exposure => Exclude */
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
select count(distinct patid) as "Step 5: multi-drug"n
from EarliestRxBph_Filtered
quit;

proc sql;
	create table EarliestRxBph_Filtered as
	select distinct
	       patid, 
		   earliest_rx_date,
		   prodcodeid, 
		   duration,
		   bph_dt,
		   baseline_dt,
		   drugsubstancename,
		   regstartdate
	from EarliestRxBph_Filtered
	group by patid, drugsubstancename
	having duration = max(duration)  /* Prefer longest treatment if two prescriptions on same date */
	;
quit;


/**************************************************************************/
/* STEP 6: Exclude if Follow-up period is less than 365 days  */
/**************************************************************************/

PROC SQL;
create table EarliestRx_washout AS
select * 
from EarliestRxBph_Filtered
having earliest_rx_date - regstartdate > 365;
quit;

/*HOW MANY PATIENTS*/
proc sql;
select count(distinct patid) as "Step 7: Washout exclusions"n
from EarliestRx_washout
quit;

**********;
/*
/**************************************************************************/
/* STEP 7: Exclude if subarachnoid hemorrhage (aSAH) occurred before Rx  */
/**************************************************************************/
/* ALSO EXCLUDE FOR MARFAN SYNDROME etc */
/* If a patient s first aSAH date (HOSP ONLY) is before earliest Rx, we drop them.    */
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
/* STEP 8: Link to ATC codes  */
/**************************************************************************/

proc sql;
	create table &out as /* change to _2, _3, and _4 per file */
	select b.*, a.ATC
	from output.BphIndexDrug b
		left  outer join rawdata.product_aurum_atc as a
		on b.prodcodeid = a.prodcodeid;
quit;

proc sort data = output.BphDrugAtc_4;
by duration;
run;

%mend;


/**************************************************************************/
/* STEP 9: COMBINE FILES */
/**************************************************************************/

%drugdata(in=rawdata.drugissue_1, out= output.bphdrugatc_1)

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


data output.all_bph_drugissue;
set output.bphdrugatc_1
output.bphdrugatc_2
output.bphdrugatc_3
output.bphdrugatc_4;
run;


/**************************************************************************/
/* STEP 10: Extract patids of patients with linked HES data 				  */
/**************************************************************************/

proc sort data = output.all_bph_drugissue;
by patid issuedate;
run;

data bph_patients;
	set output.all_bph_drugissue;
	by patid issuedate;
	if first.patid then output;
	run;

proc sql;
	create table output.linked_bph_cohort as
	select a.* , b.linkyear, b.lsoa_e, b.hes_apc_e
	from bph_patients as a 
	left outer join rawdata.aurum_eligibility_jan2026 as b on a.patid = b.patid;
quit;

*check*;
proc freq data = output.linked_bph_cohort;
	tables hes_apc_e /MISSING;
	run;

proc sql;
create table output.linked_bph_cohort AS
select *
from output.linked_bph_cohort
where lsoa_e = 1 and hes_apc_e = 1;
quit;

/*HOW MANY PATIENTS*/
proc sql;
select count(distinct patid) as n
from output.all_bph_drugissue
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
/* STEP 11: SANITY TESTING */
/**************************************************************************/
/* Checks steps throughout BPH document      */


proc sort data = output.all_bph_drugissue;
by duration patid issuedate;
run;

*** how many records still have an odd duration?***;

data test;
set output.all_bph_drugissue;
if duration < 7 then oddvalues = "TRUE";
else if duration >= 7 then oddvalues = "FALSE";
run;

proc freq data = output.all_bph_drugissue;
tables oddvalues;
run; */ only 0.07*/;


data test;
set output.all_bph_drugissue;
if duration < 7 then duration = 30;
run;
