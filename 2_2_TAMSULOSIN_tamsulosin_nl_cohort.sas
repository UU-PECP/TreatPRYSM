
/************************************************/
** 	the Treat-PRYSM project 					**
** 	by Sage Wyatt, Jos Kanning, & Shahab Abtahi **
** 	October 2025 - September 2026 				**
**	Drug - Tamsulosin							**
**												**
**	File 2.2: Exposure Generation for NL		**
/************************************************/;

/**************************************************************************/
/* Set up library references and global options                          */
/**************************************************************************/

libname rawdata "F:\Users\Wyatt003\BPH_nephrolithiasis\SAS";
libname output "F:\Users\Wyatt003\BPH_nephrolithiasis\Output";
libname codelist "F:\Users\Wyatt003\BPH_nephrolithiasis\Drug_Codelists";

options fullstimer; /* Display detailed resource usage info in log */


************************************** NEPHROLITHIASIS COHORT ****************************************;
%macro drugdata(in =, out=);

/**************************************************************************/
/* STEP 1: Extract NL drug records for the current drugissue file         */
/**************************************************************************/

*** Identify tamsulosin and standard-of-care analgesic drug records;

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
		   c.atc,
		   c.strength
	FROM &drugfile as r  
inner join codelist.&var._codes as c on strip(c.prodcodeid) = strip(r.prodcodeid);
quit;


%mend product;

*** exposure of interest: tamsulosin (same codes as the BPH script);

%product (var=tamsulosin, atccode = 'G04CA02', drugfile = &in); 
%product (var=tamsulosin_poly1, atccode = 'G04CA52', drugfile = &in); 
%product (var=tamsulosin_poly2, atccode = 'G04CA53', drugfile = &in); 
%product (var=tamsulosin_poly3, atccode = 'G04CA54', drugfile = &in); 

*** comparator: standard-of-care analgesics for acute stone management;

%product (var=analgesic_nsaid, atccode = 'M01AE%', drugfile = &in); 
%product (var=analgesic_other, atccode = 'N02%', drugfile = &in); 


*** append drug records for all drugs and create numeric exposure variable;

data appended_drugs;
set output.tamsulosin_drugs (in = a)
output.tamsulosin_poly1_drugs (in = b)
output.tamsulosin_poly2_drugs (in = c) 
output.tamsulosin_poly3_drugs (in = d)
output.analgesic_nsaid_drugs (in = e) 
output.analgesic_other_drugs (in = f);
if a or b or c or d then exposure = 1;   /* tamsulosin */
else if e or f then exposure = 2;        /* standard-of-care analgesics */
run;


*** find mg value ;

data output.nl_drugs;
    set appended_drugs;  
    length unit_found $20;

    if not missing(strength) then do;
        /* First number in the string (handles decimals) */
        mg_value = input(scan(strength, 1, 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ/'), best12.);

        /* First unit word: letters immediately after the first number */
        unit_found = scan(compress(strength, '0123456789. '), 1, '/');

        /* Convert everything to mg */
        if lowcase(unit_found) in ('microgram', 'micrograms', 'mcg') then mg_value = mg_value / 1000;
        else if lowcase(unit_found) in ('gram', 'g') then mg_value = mg_value * 1000;
        /* mg stays as-is */
    end;

    drop unit_found;
run;

/* HOW MANY PATIENTS */
proc sql;
select count(distinct patid) as "Step 1: nl drugs"n
from output.nl_drugs;
quit;


/****************************************************************************/
/* STEP 2: Generate treatment duration and mean daily dose in mg from common dosages file.*/
/****************************************************************************/

*** Import common_dosages file to extract daily dose variable;

proc sort data = codelist.common_dosages_aurum_dec2025;
by dosageid;
run;

proc sort data = output.nl_drugs;
by dosageid;
run;

data nl_dosages;
merge codelist.common_dosages_aurum_dec2025 (in=a) output.nl_drugs (in=b);
by dosageid;
if b;
run;

proc univariate data=nl_dosages;
	var daily_dose;
run;

proc univariate data=nl_dosages;
	var quantity;
run;

proc univariate data=nl_dosages;
	var duration;
run;

*** calculate mean daily dose;

data nl_dosages_mg;
set nl_dosages;
if daily_dose > 0 then mean_daily_dose = mg_value*daily_dose;
else mean_daily_dose = mg_value;
run;

*** Algorithm to determine reasonable assumed duration per prescription;
*** borrowed from ADEPT script with permission from Magdalena Gamba *;

data nl_tam_cleaning;
set nl_dosages_mg;
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


/****************************************************************************/
/* STEP 3: Join with base_cohort so only patients in our main cohort remain.*/
/****************************************************************************/

*** Join cleaned prescription records with base cohort; 
*** aSAH_gp_dt and gender carried through for the exposure-specific aSAH counts;

PROC SQL;
CREATE TABLE nl_tam AS
	SELECT T.patid, 
T.issuedate,  
T.exposure,
T.atc, 
T.dosageid, 
T.quantity,
T.assumed_duration,
T.prodcodeid,
T.mg_value,
T.mean_daily_dose,
BC.gender,
BC.regstartdate,
BC.baseline_dt,
BC.aSAH_gp_dt
	FROM nl_tam_cleaning AS T
	INNER JOIN output.nl_cohort AS BC ON BC.patid = T.patid
ORDER BY T.assumed_duration, T.patid, T.issuedate; 
quit;


/* HOW MANY PATIENTS */
proc sql;
select count(distinct patid) as "Step 3: nltam join to base"n
from nl_tam;
quit;

/**************************************************************************/
/* STEP 4: Exclude 'PrevalentUsers'                                       */
/**************************************************************************/
/* 'Prevalent users' are those who had a drug prescription 1 year before   */
/* their baseline date. We identify them by comparing issue date with the  */
/* baseline_dt in base_cohort.                                            */
/* second step removes identified prevalent users from main dataset       */

*** identify prevalent users;

proc sql;
	create table PrevalentUsers as
	select distinct patid
	from nl_tam
	where issuedate between intnx('year', baseline_dt, -1, 'same') and baseline_dt - 1;
quit;

/* HOW MANY PATIENTS */
proc sql;
select count(distinct patid) as "prevalent user #"n
from PrevalentUsers;
quit;


***  We remove those in PrevalentUsers.;
***  We only keep prescriptions dated on or after baseline.;

proc sql;
	create table output.Rx_nl_PostStart as
	select *
	from nl_tam b
	where not exists (
		select 1
		from PrevalentUsers p
		where p.patid = b.patid
		)
	and issuedate >= baseline_dt
	;
quit;

/* HOW MANY PATIENTS */
proc sql;
select count(distinct patid) as "Step 4: removing prevalent users"n
from output.Rx_nl_PostStart;
quit;


/**************************************************************************/
/* STEP 5: Identify earliest prescription date for each patient           */
/**************************************************************************/
/* Finds the minimum (earliest) issuedate among the valid prescriptions.  */
/* NOTE: no multi-drug initiator exclusion here - unlike BPH,             */
/* co-prescribing analgesics alongside tamsulosin is expected in acute    */
/* stone management, so it is not an ambiguity to exclude on.             */

proc sql;
	create table output.NlEarliestDate as
	select patid,
		   min(issuedate) as indexdate format = ddmmyy10.
	from output.Rx_nl_PostStart
	group by patid;
quit;


/* 1) We only keep rows where issuedate = indexdate.                      */
/* 2) The earliest Rx is used for cleaning in the subsequent steps, but   */
/*    all records are rejoined in the final step.                         */

proc sql;
	create table output.EarliestRxNlAll as
	select p.patid,
		   p.issuedate,
		   p.assumed_duration,
		   p.prodcodeid,
		   p.baseline_dt,
		   e.indexdate,
		   p.regstartdate,
		   p.exposure,
		   p.atc,
		   p.gender,
		   p.aSAH_gp_dt
	from output.NlEarliestDate as e
		left join output.Rx_nl_PostStart as p 
		on p.patid = e.patid
where p.issuedate = e.indexdate;
quit;


*** tie-break: if a patient has both tamsulosin and an analgesic on the index ;
*** date, assign tamsulosin as the index exposure so each patient contributes ;
*** exactly one exposure to the aSAH counts                                   ;

proc sort data = output.EarliestRxNlAll;
by patid exposure;
run;

data EarliestRxNl_Filtered;
set output.EarliestRxNlAll;
by patid;
if first.patid;
run;

/*HOW MANY PATIENTS*/
proc sql;
select count(distinct patid) as "Step 5: one index exposure per patient"n
from EarliestRxNl_Filtered;
quit;


/**************************************************************************/
/* STEP 6: Exclude if run-in period is less than 365 days                 */
/**************************************************************************/

PROC SQL;
create table EarliestRxNl_washout AS
select * 
from EarliestRxNl_Filtered
where indexdate - regstartdate > 365;
quit;

/*HOW MANY PATIENTS*/
proc sql;
select count(distinct patid) as "Step 6: Washout exclusions"n
from EarliestRxNl_washout;
quit;


/**************************************************************************/
/* STEP 7: Restrict to prescriptions relevant to the stone episode        */
/* (index Rx within 30 days on or after the NL baseline date)             */
/**************************************************************************/
/* NL-specific step, retained from the earlier NL pipeline - tamsulosin   */
/* and analgesics are used for acute stone passage, so an index Rx long   */
/* after diagnosis is unlikely to relate to that episode.                 */

PROC SQL;
create table EarliestRxNl_episode AS
select *
from EarliestRxNl_washout
where indexdate - baseline_dt <= 30
  and indexdate >= baseline_dt;
quit;

/*HOW MANY PATIENTS*/
proc sql;
select count(distinct patid) as "Step 7: relevant Rx"n
from EarliestRxNl_episode;
quit;


**********;
/*
/**************************************************************************/
/* STEP 8: Exclude if subarachnoid hemorrhage (aSAH) occurred before Rx   */
/* (COMMENTED OUT until HES APC linkage is incorporated )                 */
/**************************************************************************/

*proc sql;
*CREATE TABLE EarliestRxNl_Filtered AS
SELECT d1.* 
FROM EarliestRxNl_Filtered as d1
INNER JOIN output.linked_nl_cohort as d2 
ON d1.patid = d2.patid
	WHERE d1.aSAH_gp_dt > indexdate or d1.aSAH_gp_dt is NULL;
*quit;

/*HOW MANY PATIENTS*/
*proc sql;
*select count(distinct patid) as "Step 8: prior aSAH"n
from EarliestRxNl_Filtered 
quit;


/**************************************************************************/
/* STEP 9: Retrieving all treatment episodes from patients meeting the    */
/* exclusion criteria specified in steps 5-7                              */
/**************************************************************************/

/* FINAL PRODUCT */

*** collapse to one row per patient before the final join, so the join cannot   ;
*** fan out. Step 5 first.patid tie-break already guarantees this, so this is  ;
*** a no-op safeguard mirroring the equivalent fix in File 2_1.                  ;

proc sql;
create table EarliestRxNl_index as
select distinct patid, indexdate, exposure as index_exposure
from EarliestRxNl_episode;
quit;

proc sql;
create table &out as
select r.*, f.indexdate, f.index_exposure
from EarliestRxNl_index as f
left outer join output.Rx_nl_PostStart as r
on f.patid = r.patid;
quit;

%mend;

/**************************************************************************/
/* STEP 10: Combine all four drugissue files                              */
/**************************************************************************/

* real data input;

%drugdata(in=rawdata.drugissue_1, out=output.nldrugatc_1);

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


data output.all_nl_episodes;
set output.nldrugatc_1
output.nldrugatc_2
output.nldrugatc_3
output.nldrugatc_4;
run;

/* HOW MANY PATIENTS */
proc sql;
select count(distinct patid) as "Final Product"n
from output.all_nl_episodes;
quit;


***********************************************;
************** EXPORTING PATIDS ***************;
***********************************************;

proc sort data = output.all_nl_episodes;
by patid;
run;

data unique_patients;
set output.all_nl_episodes (keep = patid);
by patid;
if first.patid;
run;

proc sql;
	create table hes_linkage_patients_nl as
	select a.patid 
	from unique_patients as a 
	inner join rawdata.aurum_eligibility_jan2026 as b on a.patid = b.patid
	where b.lsoa_e = 1 and b.hes_apc_e = 1;
quit;

proc sql;
select count(distinct patid) as "Linked patients"n
from hes_linkage_patients_nl;
quit;

proc export data = hes_linkage_patients_nl 
outfile = "C:\Users\Wyatt003\OneDrive - Universiteit Utrecht\Documents\Codelists\LinkedPatients_tamsulosin_nl.csv"
dbms=csv
replace;
run;


***********************************************;
******** aSAH CASES BY INDEX EXPOSURE *********;
***********************************************;

*** one row per patient, using the index exposure assigned in Step 5;

proc sort data = output.all_nl_episodes;
by patid;
run;

data nl_patients_unique;
set output.all_nl_episodes;
by patid;
if first.patid;
if aSAH_gp_dt = . then aSAH = 0;
else aSAH = 1;
run;

proc format;
value expfmt 1 = "Tamsulosin"
             2 = "Standard-of-care analgesics";
run;

title "aSAH cases by index exposure - nephrolithiasis cohort";
proc freq data = nl_patients_unique;
tables index_exposure * aSAH / nocol nopercent;
format index_exposure expfmt.;
run;

title "aSAH cases by index exposure and sex - nephrolithiasis cohort";
proc freq data = nl_patients_unique;
tables index_exposure * gender * aSAH / nocol nopercent;
format index_exposure expfmt.;
run;

