
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
libname covar "F:\Users\Wyatt003\BPH_nephrolithiasis\New folder";

options fullstimer; /* Display detailed resource usage info in log */


************************************** BPH COHORT ****************************************;
%macro drugdata(in =, out=);

/**************************************************************************/
/* STEP 1: Extract BPH drug records for the current drugissue file        */
/**************************************************************************/

*** Identify tamsulosin and comparator drug records;

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

%product (var=tamsulosin, atccode = 'G04CA02', drugfile = &in); 
%product (var=tamsulosin_poly1, atccode = 'G04CA52', drugfile = &in); 
%product (var=tamsulosin_poly2, atccode = 'G04CA53', drugfile = &in); 
%product (var=tamsulosin_poly3, atccode = 'G04CA54', drugfile = &in); 

%product (var=finasteride_mono1, atccode = 'G04CB01', drugfile = &in); 
%product (var=finasteride_mono2, atccode = 'D11AX10', drugfile = &in);

%product (var=alfuzosin, atccode = 'G04CA01', drugfile = &in);  




*** append drugs records for all drugs and create numeric exposure variable;

data output.bph_drugs;
set output.tamsulosin_drugs (in = a)
output.tamsulosin_poly1_drugs (in = b)
output.tamsulosin_poly2_drugs (in = c) 
output.tamsulosin_poly3_drugs (in = d)
output.alfuzosin_drugs (in=e) 
output.finasteride_mono1_drugs (in=f)  
output.finasteride_mono2_drugs (in=g);
if a or b or c or d then exposure = 1;
else if e then exposure = 2;
else if f or g then exposure = 3;
run;




/* HOW MANY PATIENTS */
proc sql;
select count(distinct patid) as "Step 1: bph drugs"n
from output.bph_drugs;
quit;
* Patient Count per file
133816
134912
133196
134417
TOTAL 536341
*;

* Exposure extraction check by Shahab - Aug 2026 ;

Proc sort data = output.bph_drugs;
by patid issuedate;
run;

Data BPH_users ;
Set output.bph_drugs;
by patid;
if first.patid ;
run;
* 134,417 unique BPH drug users, 90% tamsulosin user, 4% alfuzosin user, and 6% finasteride users ;

Proc freq data = BPH_users ;
table exposure ;
run;

Data Drusissue_1 ;
Set rawdata.Drugissue_1 ;
informat new_prodcode 20. ;
new_prodcode = input (prodcodeId, 20.);
format new_prodcode 20. ;
run;

Data Drusissue_1 ;
Set Drusissue_1 ;
Drop prodcodeId ;
Rename new_prodcode = ProdCodeID ;
run;

data Tamsulosin_cod ;
	infile "F:\Users\Wyatt003\BPH_nephrolithiasis\Drug_Codelists\Tamsulosin_All codes_SA.txt" dsd dlm='09'x firstobs=2 truncover;
	input ProdCodeID;
	informat 	ProdCodeID 20.;
	format 		ProdCodeID 20.;
run;

data Alfuzosin_cod ;
	infile "F:\Users\Wyatt003\BPH_nephrolithiasis\Drug_Codelists\Alfuzosin_All codes_SA.txt" dsd dlm='09'x firstobs=2 truncover;
	input ProdCodeID;
	informat 	ProdCodeID 20.;
	format 		ProdCodeID 20.;
run;

data Finasteride_cod ;
	infile "F:\Users\Wyatt003\BPH_nephrolithiasis\Drug_Codelists\Finasteride_All codes_SA.txt" dsd dlm='09'x firstobs=2 truncover;
	input ProdCodeID;
	informat 	ProdCodeID 20.;
	format 		ProdCodeID 20.;
run;

proc sort data = Tamsulosin_cod;
	by ProdCodeID;
run;

proc sort data = Alfuzosin_cod;
	by ProdCodeID;
run;

proc sort data = Finasteride_cod;
	by ProdCodeID;
run;

proc sort data = Drusissue_1;
	by ProdCodeID;
run;

data covar.Tamsulosin_1;
	merge Drusissue_1 (in=x keep=patid ProdCodeID issuedate) Tamsulosin_cod (in=y keep=ProdCodeID);
	by ProdCodeID;
	if x and y;
run;

data covar.Alfuzosin_1;
	merge Drusissue_1 (in=x keep=patid ProdCodeID issuedate) Alfuzosin_cod (in=y keep=ProdCodeID);
	by ProdCodeID;
	if x and y;
run;

data covar.Finasteride_1;
	merge Drusissue_1 (in=x keep=patid ProdCodeID issuedate) Finasteride_cod (in=y keep=ProdCodeID);
	by ProdCodeID;
	if x and y;
run;

Proc sort data = covar.Tamsulosin_1;
by patid;
run;

Proc sort data = covar.Alfuzosin_1;
by patid;
run;

Proc sort data = covar.Finasteride_1;
by patid;
run;

Data covar.All_BPH_users ;
Set covar.Tamsulosin_1 (in=x) covar.Alfuzosin_1 (in=y) covar.Finasteride_1 (in=z) ;
by patid;
if x then expo = 1 ;
if y then expo = 2 ;
if z then expo = 3 ;
run;

Data unique_users ;
Set covar.All_BPH_users; 
by patid;
if first.patid;
run;
* 133,816 unique 3 drug users in set 1 ;

Proc freq data = unique_users ;
table expo ;
run;

/****************************************************************************/
/* STEP 2: Generate treatment duration and mean daily dose in mg from common dosages file.*/
/****************************************************************************/

*** Import common_dosages file to extract daily dose variable;

proc sort data = codelist.common_dosages_aurum_dec2025;
by dosageid;
run;

proc sort data = output.bph_drugs;
by dosageid;
run;

data bph_dosages;
merge codelist.common_dosages_aurum_dec2025 (in=a) output.bph_drugs (in=b);
by dosageid;
if b;
run;

*** Algorithm to determine reasonable assumed duration per prescription;
*** borrowed from ADEPT script with permission from Magdalena Gamba *;

data bph_tam_cleaning;
set bph_dosages;
if daily_dose > 5 or daily_dose = . then daily_dose = 1;
if daily_dose = 0 then daily_dose = 0.5;
if quantity > 90 then quantity = 90;
if quantity > 0 and quantity ne . then assumed_duration = quantity/daily_dose;
if assumed_duration = . and duration ne . and duration > 0 and duration < 90 then assumed_duration = duration;
if assumed_duration = . or assumed_duration < 1 then assumed_duration = 30;
run; 


/****************************************************************************/
/* STEP 3: Join with base_cohort so only patients in our main cohort remain.*/
/****************************************************************************/

*** Join cleaned prescription records with base cohort; 

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
BC.regstartdate,
BC.baseline_dt
	FROM bph_tam_cleaning AS T
	INNER JOIN output.bph_cohort AS BC ON BC.patid = T.patid
ORDER BY T.assumed_duration, T.patid, T.issuedate; 
quit;


/* HOW MANY PATIENTS */
proc sql;
select count(distinct patid) as "Step 3: bphtam join to base"n
from bph_tam;
quit;

* Patient Count per file
123829
124966
122092
123781
TOTAL 494668
*;

* test by Shahab ;
Data basejoined_set1 ;
merge output.bph_cohort (in=x keep= patid baseline_dt) covar.All_BPH_users (in=y keep= patid issuedate expo) ;
by patid ;
if x and y ;
run;

Data basejoined_set2 ;
Set basejoined_set1 ;
by patid;
if first.patid;
run;
* 123,829 left after checking against the bast cohort - Set 1 only ;


/**************************************************************************/
/* STEP 4: Exclude 'PrevalentUsers'                                       */
/**************************************************************************/
/* 'Prevalent users' are those who had a drug prescription 1 year before   */
/* their baseline date. We identify them by comparing issue date with the  */
/* bph_dt in base_cohort. */
/* second step removes identified prevalent users from main dataset */

*** identify prevalent users;

proc sql;
	create table PrevalentUsers as
	select distinct patid
	from bph_tam
	where issuedate between intnx('year', baseline_dt, -1, 'same') and baseline_dt - 1;
quit;

***  We remove those in PrevalentUsers.;
***  We only keep prescriptions dated on or after baseline.;

proc sql;
	create table output.Rx_bph_PostStart as
	select *
	from bph_tam b
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
from output.Rx_bph_PostStart;
quit;
* Patient Count per file
78122
78400
76103
76754
TOTAL 309379
*;

* Shahab tests in base SAS ;
Data prevalent_use1 ;
Set basejoined_set1 ;
by patid;
if (baseline_dt - 366) < issuedate < baseline_dt ;
run;

Proc sort data = prevalent_use1 ;
by patid;
run;

Data prevalent_use2;
Set prevalent_use1 ;
by patid;
if first.patid;
run;
* 38,097 unique patient prevalent user of any BPH drug in 1-y before cohort entry date ;

Data New_users ;
merge basejoined_set1 (in=x) prevalent_use2 (in=y) ;
by patid;
if x and not y ;
if issuedate >= baseline_dt ;
run;

Data New_users1 ;
Set New_users ;
by patid;
if first.patid ;
run;
* 78,125 new users of all 3 BPH drugs in Set 1 only ;


/**************************************************************************/
/* STEP 5: Identify earliest prescription date for each patient and exclude multi-drug initiators         */
/**************************************************************************/
/* Finds the minimum (earliest) eventdate among the valid prescriptions.  */

proc sql;
	create table output.BphEarliestDate as
	select patid,
		   min(issuedate) as indexdate format = ddmmyy10.
	from output.Rx_bph_PostStart
	group by patid;
quit;


* Check by Shahab ;
Proc sort data = New_users ;
by patid issuedate ;
run;

Data New_users3;
Set New_users ;
by patid;
informat indexdate ddmmyy10. ;
if first.patid then indexdate = issuedate;
format indexdate ddmmyy10. ;
retain indexdate ;
run;

Data New_users4 ;
Set New_users3 ;
by patid ;
if issuedate = indexdate ;
if first.patid then numpers = 0 ;
numpers + 1;
run;

Data New_users5;
Set New_users4 ;
by patid;
if numpers >= 2 ;
run;

Data New_users6 ;
merge New_users5 (in=x keep=patid) New_users3 (in=y);
by patid;
if x and y;
if issuedate = indexdate ;
run;

Data New_users7 ;
Set New_users6 ;
by patid;
if expo = 1 then expox = 10; 
	else if expo = 2 or 3 then expox = 1 ;
if first.patid then sum_expo = 0 ;
sum_expo = sum_expo + expox ;
retain sum_expo ;
run;

Data New_users8 ;
Set New_users7 ;
by patid;
if sum_expo not in (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 130) ;
run;

Data New_users9 ;
Set New_users8 ;
by patid;
if first.patid;
Drop baseline_dt issuedate indexdate expo expox sum_expo ;
run;
* 4155 patients used tamsulosin together with alfuzosin/ finasteride at index date and to be deleted, Set 1 only ;

Data New_users_nocombi ;
merge New_users1 (in=x) New_users9 (in=y) ;
by patid;
if x and not y ;
run;
* 73,970 unique patients new users of all 3 BPH drugs, and no combi of tamsulosin with alfuzosin/finasteride, in Set 1 ;


/* 1) We only keep rows where issuedate = indexdate.               */
/* 2) We call this 'EarliestRxAll'.                                       */
/* the earliest Rx will be used for cleaning in the subsequent steps, but then all records will
be rejoined in the final step for creation of treatment episodes */


proc sql;
	create table output.EarliestRxBphAll as
	select p.patid,
		   p.issuedate,
		   p.assumed_duration,
		   p.prodcodeid,
		   p.baseline_dt,
		   e.indexdate,
		   p.regstartdate,
		   p.exposure,
		   p.atc
	from output.BphEarliestDate as e
		left join output.Rx_bph_PostStart as p 
		on p.patid = e.patid
where p.issuedate = e.indexdate;
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
	create table whichMulti as
	select distinct a.patid, a.exposure
	from output.EarliestRxBphAll as a
	inner join ExcludeMulti as b on a.patid = b.patid
	order by a.patid, a.exposure;
quit;

data combos;
set whichMulti;
by patid;
length combo $60;
retain combo;
if first.patid then combo = '';
combo = catx(' + ', combo, put(exposure, 8.));
if last.patid then output;
keep patid combo;
run;

proc freq data = combos noprint;
tables combo / out = combo_counts;
run;

proc sql;
	create table EarliestRxBph_Filtered as
	select *
	from output.EarliestRxBphAll
	where patid not in (select patid from ExcludeMulti);
quit;

/*HOW MANY PATIENTS*/
proc sql;
select count(distinct patid) as "Step 5: no multi-drug initiators"n
from EarliestRxBph_Filtered;
quit;

* Patient Count per file
73607
74293
71925
72641
TOTAL 292466
*;






*** exclude if first drug issue is after the end of study period;

data EarliestRxBph_Filtered;
set EarliestRxBph_Filtered;
where indexdate <= '31MAR2025'd;
run;

/*HOW MANY PATIENTS*/
proc sql;
select count(distinct patid) as "Step 5: study period index date"n
from EarliestRxBph_Filtered;
quit;

* Patient Count per file
72836
73490
71183
71856
TOTAL 289365 
*;
/**************************************************************************/
/* STEP 6: Exclude if run-in period is less than 365 days              */
/**************************************************************************/

PROC SQL;
create table EarliestRxBph_Filtered AS
select * 
from EarliestRxBph_Filtered
having indexdate - regstartdate > 365;
quit;

/*HOW MANY PATIENTS*/
proc sql;
select count(distinct patid) as "Step 6: Washout exclusions"n
from EarliestRxBph_Filtered;
quit;
* Patient Count per file
64708
65533
62784
63611
TOTAL 256636
*;

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
*CREATE TABLE EarliestRxBph_Filtered AS
SELECT d1.* , d2.patid, d2.aSAH_gp_dt
FROM EarliestRxBph_Filtered as d1
INNER JOIN output.linked_bph_cohort as d2 
ON d1.patid = d2.patid
	WHERE d2.aSAH_gp_dt > indexdate or d2.aSAH_gp_dt is NULL;
*quit;

/*HOW MANY PATIENTS*/
*proc sql;
*select count(distinct patid) as "Step 8: prior aSAH"n
from EarliestRxBph_Filtered 
quit;


/**************************************************************************/
/* STEP 8: Retrieiving all treatment episodes from patients with exclusion criteria specified in steps 5 & 6   */
/**************************************************************************/

/* FINAL PRODUCT */

proc sql; 
create table EarliestRxBph_Index as
select distinct patid, indexdate
from EarliestRxBph_Filtered;
quit;

proc sql;
create table &out as
select r.*, f.indexdate
from EarliestRxBph_Index as f
left outer join output.Rx_bph_PostStart as r
on f.patid = r.patid;
quit;

%mend;

/**************************************************************************/
/* STEP 9: Combine all four drugissue files                              */
/**************************************************************************/

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


***********************************************;
************** EXPORTING PATIDS ***************;
***********************************************;

proc sort data = output.all_bph_episodes;
by patid;
run;


data unique_patients;
set output.all_bph_episodes (keep = patid);
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
outfile = "C:\Users\Wyatt003\OneDrive - Universiteit Utrecht\Documents\Export\LinkedPatients_tamsulosin.csv"
dbms=csv
replace;
run;
* Patient Count TOTAL 245,585*;

/* For testing 

* HOW MANY PATIENTS? 264,340 ;
proc sql;
select count(distinct patid) as "Final Product"n
from output.all_bph_episodes
quit;


* data subset test for shorter runtime;

data output.drugissue_TEST;
set rawdata.drugissue_2;
where input(patid, 19.) > 2000000000 and input(patid, 19.) < 3000000000;
run;


%drugdata(in=output.drugissue_TEST, out=output.bph_episodes_TEST);

*/
