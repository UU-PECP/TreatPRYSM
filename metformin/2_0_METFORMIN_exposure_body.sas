
/************************************************/
** 	the Treat-PRYSM project 					**
** 	Drug - Metformin							**
**												**
**	File 2_0: Exposure generation - SHARED BODY **
**	Modelled on tamsulosin/2_1 (BPH, active-    **
**	comparator design). %include this from a    **
**	per-cohort driver (2_1/2_2) that has already**
**	set the %let parameters below. Do not run   **
**	this file directly.                          **
**												**
**	Required %let parameters from the driver:   **
**	  &cohort_label   - e.g. su / sglt2i (used  **
**	                    in output dataset names)**
**	  &startdate      - cohort study start, e.g.**
**	                    '01JAN2004'd            **
**	  &enddate        - cohort study end, e.g.  **
**	                    '31DEC2013'd            **
**	  &comparator_file - path to the comparator **
**	                    codelist txt (SU or     **
**	                    SGLT2i)                  **
**	  &comparator_name - label used in comments **
**	                    / proc format only      **
/************************************************/;

libname rawdata "F:\Users\Wyatt003\Metformin\Raw_Data";
libname output "F:\Users\Wyatt003\Metformin\Output";
libname codelist "F:\Users\Wyatt003\Metformin\Drug_Codes";

options fullstimer;

/**************************************************************************/
/* STEP 0: Import codelists (ProdCodeId-level exports from the CPRD Aurum */
/* codebrowser - unlike tamsulosin's ATC-LIKE codelists, these are        */
/* explicit product lists, so no ATC lookup step is needed).              */
/**************************************************************************/

data metformin_cod;
	infile "F:\Users\Wyatt003\Metformin\Drug_Codes\metformin.txt" dsd dlm='09'x firstobs=2 truncover;
	length ProdCodeId $19 DMDCode $19 TermfromEMIS $200 ProductName $200
	       drugsubstancename $100 substancestrength $40 formulation $40
	       routeofadministration $20 bnfcode $10;
	input ProdCodeId :$19. DMDCode :$19. TermfromEMIS :$200. ProductName :$200.
	      drugsubstancename :$100. substancestrength :$40. formulation :$40.
	      routeofadministration :$20. bnfcode :$10. DrugIssues;
run;

data comparator_cod;
	infile "&comparator_file" dsd dlm='09'x firstobs=2 truncover;
	length ProdCodeId $19 DMDCode $19 TermfromEMIS $200 ProductName $200
	       drugsubstancename $100 substancestrength $40 formulation $40
	       routeofadministration $20 bnfcode $10;
	input ProdCodeId :$19. DMDCode :$19. TermfromEMIS :$200. ProductName :$200.
	      drugsubstancename :$100. substancestrength :$40. formulation :$40.
	      routeofadministration :$20. bnfcode :$10. DrugIssues;
run;

data mg_lookup;
	infile "F:\Users\Wyatt003\Metformin\Drug_Codes\mg_value_lookup.txt" dsd dlm='09'x firstobs=2 truncover;
	length ProdCodeId $19;
	input ProdCodeId :$19. mg_value;
run;

%macro drugdata(in =, out=);

/**************************************************************************/
/* STEP 1: Extract metformin and comparator drug records for the current  */
/* drugissue file, using our own ProdCodeId codelists.                    */
/*                                                                          */
/* NOTE: unlike tamsulosin/2_1, no separate "poly" ProdCodeId groups are  */
/* needed here - metformin monotherapy AND its non-comparator combination */
/* products (TZD/DPP-4i) are already a single flat codelist              */
/* (metformin/codelists/raw_cprd_browser_exports/metformin.txt); products */
/* combining metformin with THIS cohort's comparator class were removed   */
/* from both codelists at the source, so there is no ProdCodeId overlap   */
/* to worry about (see metformin/README.md).                              */
/**************************************************************************/

proc sql;
	CREATE TABLE output.metformin_drugs AS
	SELECT r.patid,
		   r.issuedate,
		   r.dosageid,
		   r.quantity,
		   r.duration,
		   r.prodcodeid
	FROM &in as r
	inner join metformin_cod as c on strip(c.prodcodeid) = strip(r.prodcodeid);
quit;

proc sql;
	CREATE TABLE output.comparator_drugs AS
	SELECT r.patid,
		   r.issuedate,
		   r.dosageid,
		   r.quantity,
		   r.duration,
		   r.prodcodeid
	FROM &in as r
	inner join comparator_cod as c on strip(c.prodcodeid) = strip(r.prodcodeid);
quit;

data output.&cohort_label._drugs;
set output.metformin_drugs (in = a)
    output.comparator_drugs (in = b);
if a then exposure = 1;  /* metformin */
else if b then exposure = 2;  /* comparator: &comparator_name */
run;

proc sql;
create table output.&cohort_label._drugs as
select b.*, m.mg_value
from output.&cohort_label._drugs as b
inner join mg_lookup as m on b.prodcodeid = m.prodcodeid;
quit;

/****************************************************************************/
/* STEP 2: Generate treatment duration and mean daily dose in mg from       */
/* common dosages file (generic dosageid -> daily_dose reference table,    */
/* not drug-specific - same table tamsulosin uses).                        */
/****************************************************************************/

proc sort data = codelist.common_dosages_aurum_dec2025;
by dosageid;
run;

proc sort data = output.&cohort_label._drugs;
by dosageid;
run;

data &cohort_label._dosages;
merge codelist.common_dosages_aurum_dec2025 (in=a) output.&cohort_label._drugs (in=b);
by dosageid;
if b;
run;

*** Algorithm to determine reasonable assumed duration per prescription;
*** borrowed from ADEPT script with permission from Magdalena Gamba, same;
*** as tamsulosin/2_1 - not drug-specific;

data &cohort_label._cleaning;
set &cohort_label._dosages;
if daily_dose > 5 or daily_dose = . then daily_dose = 1;
if daily_dose = 0 then daily_dose = 0.5;
if quantity > 90 then quantity = 90;
if quantity > 0 and quantity ne . then assumed_duration = quantity/daily_dose;
if assumed_duration = . and duration ne . and duration > 0 and duration < 90 then assumed_duration = duration;
if assumed_duration = . or assumed_duration < 1 then assumed_duration = 30;
mean_daily_dose = mg_value * daily_dose;
run;

/****************************************************************************/
/* STEP 3: Join with base_cohort (output.t2dm_cohort, from 1_1) so only     */
/* patients in the T2DM base cohort remain.                                 */
/****************************************************************************/

PROC SQL;
CREATE TABLE &cohort_label._basejoined AS
	SELECT T.patid,
T.issuedate,
T.exposure,
T.dosageid,
T.quantity,
T.assumed_duration,
T.prodcodeid,
T.mg_value,
T.mean_daily_dose,
BC.gender,
BC.regstartdate,
BC.baseline_dt,
BC.aSAH_apc_dt
	FROM &cohort_label._cleaning AS T
	INNER JOIN output.t2dm_cohort AS BC ON BC.patid = T.patid
ORDER BY T.assumed_duration, T.patid, T.issuedate;
quit;

/* HOW MANY PATIENTS */
proc sql;
select count(distinct patid) as "Step 3: join to T2DM base"n
from &cohort_label._basejoined;
quit;

/**************************************************************************/
/* STEP 4: Exclude 'PrevalentUsers'                                       */
/* Same as tamsulosin/2_1: a prevalent user is anyone with a prescription  */
/* for EITHER exposure or comparator within 1 year before baseline_dt.    */
/* Operating on the combined (both-exposure) table already gives the      */
/* "new user of exposure OR comparator" definition the protocol requires. */
/**************************************************************************/

proc sort data = &cohort_label._basejoined;
by patid;
run;

Data &cohort_label._prevalent1;
Set &cohort_label._basejoined;
by patid;
if (baseline_dt - 366) < issuedate < baseline_dt;
run;

Proc sort data = &cohort_label._prevalent1;
by patid;
run;

Data &cohort_label._prevalent2;
Set &cohort_label._prevalent1;
by patid;
if first.patid;
run;

Data output.Rx_&cohort_label._PostStart;
merge &cohort_label._basejoined (in=x) &cohort_label._prevalent2 (in=y);
by patid;
if x and not y;
if issuedate >= baseline_dt;
run;

/* HOW MANY PATIENTS */
proc sql;
select count(distinct patid) as "Step 4: removing prevalent users"n
from output.Rx_&cohort_label._PostStart;
quit;

/**************************************************************************/
/* STEP 5: Identify earliest prescription date for each patient, and      */
/* exclude simultaneous same-day initiators of BOTH metformin and the     */
/* comparator (as separate products - fixed-dose combination products     */
/* were already excluded from both codelists at the source, see 2_0's     */
/* header comment).                                                        */
/*                                                                          */
/* NOTE: this is a simpler, more direct equivalent of tamsulosin/2_1's    */
/* Step 5 (which used a sum-encoding trick to disambiguate 3 exposure     */
/* groups). With only 2 groups, checking for >1 distinct exposure value   */
/* on the index date is exactly equivalent and easier to read/audit.      */
/**************************************************************************/

Data New_users1;
Set output.Rx_&cohort_label._PostStart;
indexdate = issuedate;
format indexdate ddmmyy10;
by patid;
if first.patid;
run;

Proc sort data = output.Rx_&cohort_label._PostStart;
by patid issuedate;
run;

Data New_users3;
Set output.Rx_&cohort_label._PostStart;
by patid;
informat indexdate ddmmyy10.;
if first.patid then indexdate = issuedate;
format indexdate ddmmyy10.;
retain indexdate;
run;

Data New_users4;
Set New_users3;
by patid;
if issuedate = indexdate;
run;

proc sort data = New_users4 out=New_users4_sorted nodupkey;
by patid exposure;
run;

Data simultaneous_initiators;
Set New_users4_sorted;
by patid;
if first.patid then n_exposures = 0;
n_exposures + 1;
run;

Data simultaneous_initiators_flag;
Set simultaneous_initiators;
by patid;
if last.patid and n_exposures > 1;
run;
* patients flagged here initiated metformin and the comparator as        ;
* separate products on the same index date - excluded below              ;

Data New_users_nocombi;
merge New_users1 (in=x) simultaneous_initiators_flag (in=y keep=patid);
by patid;
if x and not y;
run;

/*HOW MANY PATIENTS*/
proc sql;
select count(distinct patid) as "Step 5: no simultaneous initiators"n
from New_users_nocombi;
quit;

/**************************************************************************/
/* STEP 6: exclude if first drug issue is outside the cohort's study      */
/* period                                                                  */
/**************************************************************************/

data Patients_in_study_period;
set New_users_nocombi;
where &startdate <= indexdate <= &enddate;
run;

/*HOW MANY PATIENTS*/
proc sql;
select count(distinct patid) as "Step 6: study period index date"n
from Patients_in_study_period;
quit;

/**************************************************************************/
/* STEP 7: Exclude if run-in period is less than 365 days                 */
/**************************************************************************/

PROC SQL;
create table Min_365_days_washout AS
select *
from Patients_in_study_period
having indexdate - regstartdate > 365;
quit;

/*HOW MANY PATIENTS*/
proc sql;
select count(distinct patid) as "Step 7: Washout exclusions"n
from Min_365_days_washout;
quit;

/**************************************************************************/
/* STEP 8: Exclude if aSAH occurred before Rx                              */
/**************************************************************************/

proc sql;
CREATE TABLE aSAH_Filter AS
SELECT d1.*
FROM Min_365_days_washout as d1
WHERE d1.aSAH_apc_dt > indexdate or d1.aSAH_apc_dt is NULL;
quit;

/*HOW MANY PATIENTS*/
proc sql;
select count(distinct patid) as "Step 8: prior aSAH"n
from aSAH_Filter;
quit;

/**************************************************************************/
/* STEP 9: Retrieve all treatment episodes for patients meeting the       */
/* exclusion criteria specified in Steps 5-8                              */
/**************************************************************************/

proc sql;
create table Distinct_patients as
select distinct patid, indexdate
from aSAH_Filter;
quit;

proc sql;
create table &out as
select r.*, f.indexdate
from Distinct_patients as f
left outer join output.Rx_&cohort_label._PostStart as r
on f.patid = r.patid;
quit;

%mend;

/**************************************************************************/
/* STEP 10: Combine all raw drugissue files (assumes 4, as in tamsulosin; */
/* adjust the number of %drugdata calls to match the metformin extract). */
/**************************************************************************/

%drugdata(in=rawdata.drugissue_1, out=output.&cohort_label._drugatc_1);

proc datasets library = work kill nolist;
run;
quit;

%drugdata(in=rawdata.drugissue_2, out=output.&cohort_label._drugatc_2);

proc datasets library = work kill nolist;
run;
quit;

%drugdata(in=rawdata.drugissue_3, out=output.&cohort_label._drugatc_3);

proc datasets library = work kill nolist;
run;
quit;

%drugdata(in=rawdata.drugissue_4, out=output.&cohort_label._drugatc_4);

proc datasets library = work kill nolist;
run;
quit;

data output.all_&cohort_label._episodes_raw;
set output.&cohort_label._drugatc_1
output.&cohort_label._drugatc_2
output.&cohort_label._drugatc_3
output.&cohort_label._drugatc_4;
run;

proc sql;
select count(distinct patid) as "All Episodes"n
from output.all_&cohort_label._episodes_raw
quit;

***********************************************;
************** EXPORTING PATIDS ***************;
***********************************************;

proc sort data = output.all_&cohort_label._episodes_raw;
by patid;
run;

data unique_patients;
set output.all_&cohort_label._episodes_raw (keep = patid);
by patid;
if first.patid;
run;

proc sql;
	create table hes_linkage_patients as
	select a.patid
	from unique_patients as a
	inner join rawdata.aurum_eligibility_jan2026 as b on a.patid = b.patid
	where b.lsoa_e = 1 and b.hes_apc_e = 1;
quit;

proc sql;
select count(distinct patid) as "Linked patients"n
from hes_linkage_patients;
quit;

proc export data = hes_linkage_patients
outfile = "C:\Users\Wyatt003\OneDrive - Universiteit Utrecht\Documents\Export\LinkedPatients_metformin_&cohort_label..txt"
dbms=tab
replace;
run;

proc sql;
create table output.all_&cohort_label._episodes as
select r.*
from output.all_&cohort_label._episodes_raw as r
where r.patid in (select patid from hes_linkage_patients);
quit;

proc sql;
select count(distinct patid) as "Linked patients - episodes file"n
from output.all_&cohort_label._episodes;
quit;

***********************************************;
********* aSAH CASES BY INDEX EXPOSURE *********;
***********************************************;

proc sort data = output.all_&cohort_label._episodes;
by patid;
run;

data &cohort_label._patients_unique;
set output.all_&cohort_label._episodes;
by patid;
if first.patid;
if aSAH_apc_dt = . then aSAH = 0;
else aSAH = 1;
run;

proc format;
value expfmt 1 = "Metformin"
             2 = "&comparator_name";
run;

title "aSAH cases by index exposure - &cohort_label cohort";
proc freq data = &cohort_label._patients_unique;
tables exposure * aSAH / nocol nopercent;
format exposure expfmt.;
run;

title "aSAH cases by index exposure and sex - &cohort_label cohort";
proc freq data = &cohort_label._patients_unique;
tables exposure * gender * aSAH / nocol nopercent;
format exposure expfmt.;
run;
title;
