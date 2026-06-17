
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
libname codelist "C:\Users\Wyatt003\OneDrive - Universiteit Utrecht\Documents\Codelists\3_MagdasCodes";

options fullstimer;

************************************** NEPHROLITHIASIS COHORT ****************************************;

*** FIRST FILE ***;

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
		rawdata.drugissue_1 AS med
	INNER JOIN
		codelist.bph_drugs_fixed AS bphcod
		ON med.ProdCodeId = bphcod.ProdCodeId
	WHERE bphcod.drugsubstancename = "Tamsulosin";
quit;


/****************************************************************************/
/* STEP 2: Clean duration and calculate dose variables                      */
/****************************************************************************/
/* For records with duration < 7 and positive quantity, assign quantity as duration */
/* For unusually high durations (> 365), assign median duration (28 days)   */

data nl_tam_cleaning1;
set output.bph_drugs;
if quantity < 1 AND duration < 7 then duration = 1;
else if quantity >= 1 AND duration < 7 then duration = quantity;
else if duration > 365 then duration = 30;
else duration = duration;
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
mean_daily_dose = mg_dose * calc_dose; /* fixed: mg_dose not mg_value */
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
	FROM nl_tam_cleaning4 AS T
	LEFT OUTER JOIN output.nl_cohort AS BC ON BC.patid = T.patid
ORDER BY T.patid, T.issuedate; 
quit;


/**************************************************************************/
/* STEP 3: Exclude 'PrevalentUsers'                                       */
/**************************************************************************/
/* 'Prevalent users' are those who had a drug prescription 1 year before  */
/* their baseline_dt. We identify them by comparing issuedate with baseline_dt.       */

proc sql;
	create table PrevalentUsers as
	select distinct d1.patid
	from output.nl_cohort d1
		inner join nl_tam d2
		on d1.patid = d2.patid
	where d2.issuedate between intnx('year', d1.baseline_dt, -1) and d1.baseline_dt - 1;
quit;

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
	and d2.issuedate >= d1.baseline_dt;
quit;


/**************************************************************************/
/* STEP 4: Identify earliest prescription date for each patient           */
/**************************************************************************/

proc sql;
	create table output.NlEarliestDate as
	select patid,
		   min(issuedate) as earliest_rx_date format = ddmmyy10.
	from output.Rx_PostStart
	group by patid;
quit;

proc sql;
	create table output.EarliestRxNlAll as
	select p.patid,
		   p.exposure,
		   p.issuedate,
		   p.duration,
		   p.prodcodeid,
		   p.nl_dt,
		   p.baseline_dt,
		   e.earliest_rx_date,
		   p.regstartdate,
		   p.drugsubstancename
	from output.Rx_PostStart as p
		inner join output.NlEarliestDate as e
		on p.patid = e.patid
	where p.issuedate = e.earliest_rx_date;
quit;


/**************************************************************************/
/* STEP 5: Exclude patients who have more than one record on earliest Rx  */
/**************************************************************************/

proc sql;
	create table ExcludeMulti as
	select patid
	from output.EarliestRxNlAll
	group by patid
	having count(distinct exposure) > 1
	;
quit;

proc sql;
	create table EarliestRxNl_Filtered as
	select *
	from output.EarliestRxNlAll
	where patid not in (select patid from ExcludeMulti);
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
		   baseline_dt,
		   drugsubstancename,
		   regstartdate
	from EarliestRxNl_Filtered
	group by patid, exposure
	having duration = max(duration)
	;
quit;

/**************************************************************************/
/* STEP 7: Exclude if washout period is less than 365 days                */
/**************************************************************************/

PROC SQL;
create table EarliestRx_washout AS
select * 
from EarliestRxNl_Filtered
having earliest_rx_date - regstartdate > 365;
quit;


/**************************************************************************/
/* STEP 8: Exclude if aSAH occurred before Rx                             */
/**************************************************************************/
/* NOTE: DO NOT RUN UNTIL HES APC LINKAGE */

proc sql;
CREATE TABLE EarliestRx_aSah_Exclusion AS
SELECT d1.*, d2.patid, d2.aSAH_gp_dt
FROM EarliestRx_washout as d1
INNER JOIN output.nl_cohort as d2 
ON d1.patid = d2.patid
	WHERE d2.aSAH_gp_dt > earliest_rx_date or d2.aSAH_gp_dt is NULL;
quit;


/**************************************************************************/
/* STEP 9: Keep only the same drug as earliest for final prescription set */
/**************************************************************************/

proc sql;
	create table output.NlIndexDrug as
	select p.*
	from output.Rx_PostStart p
		inner join EarliestRx_aSah_Exclusion e
		on p.patid = e.patid
	where p.exposure = e.exposure
	  and p.issuedate >= e.earliest_rx_date 
	order by p.patid, p.issuedate;
quit;

*** Link to ATC codes ***;

proc sql;
	create table output.NlDrugAtc_1 as
	select b.*, a.ATC
	from output.NlIndexDrug b
		left outer join rawdata.product_aurum_atc as a
		on b.prodcodeid = a.prodcodeid;
quit;

proc sort data = output.NlDrugAtc_1;
by duration;
run;

proc datasets library=work kill nolist;
run;
quit;

*** SECOND FILE ***;

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
		rawdata.drugissue_2 AS med
	INNER JOIN
		codelist.bph_drugs_fixed AS bphcod
		ON med.ProdCodeId = bphcod.ProdCodeId
	WHERE bphcod.drugsubstancename = "Tamsulosin";
quit;


/****************************************************************************/
/* STEP 2: Clean duration and calculate dose variables                      */
/****************************************************************************/

data nl_tam_cleaning1;
set output.bph_drugs;
if quantity < 1 AND duration < 7 then duration = 1;
else if quantity >= 1 AND duration < 7 then duration = quantity;
else if duration > 365 then duration = 30;
else duration = duration;
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
	FROM nl_tam_cleaning4 AS T
	LEFT OUTER JOIN output.nl_cohort AS BC ON BC.patid = T.patid
ORDER BY T.patid, T.issuedate; 
quit;


/**************************************************************************/
/* STEP 3: Exclude 'PrevalentUsers'                                       */
/**************************************************************************/

proc sql;
	create table PrevalentUsers as
	select distinct d1.patid
	from output.nl_cohort d1
		inner join nl_tam d2
		on d1.patid = d2.patid
	where d2.issuedate between intnx('year', d1.baseline_dt, -1) and d1.baseline_dt - 1;
quit;

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
	and d2.issuedate >= d1.baseline_dt;
quit;


/**************************************************************************/
/* STEP 4: Identify earliest prescription date for each patient           */
/**************************************************************************/

proc sql;
	create table output.NlEarliestDate as
	select patid,
		   min(issuedate) as earliest_rx_date format = ddmmyy10.
	from output.Rx_PostStart
	group by patid;
quit;

proc sql;
	create table output.EarliestRxNlAll as
	select p.patid,
		   p.exposure,
		   p.issuedate,
		   p.duration,
		   p.prodcodeid,
		   p.nl_dt,
		   p.baseline_dt,
		   e.earliest_rx_date,
		   p.regstartdate,
		   p.drugsubstancename
	from output.Rx_PostStart as p
		inner join output.NlEarliestDate as e
		on p.patid = e.patid
	where p.issuedate = e.earliest_rx_date;
quit;


/**************************************************************************/
/* STEP 5: Exclude patients who have more than one record on earliest Rx  */
/**************************************************************************/

proc sql;
	create table ExcludeMulti as
	select patid
	from output.EarliestRxNlAll
	group by patid
	having count(distinct exposure) > 1
	;
quit;

proc sql;
	create table EarliestRxNl_Filtered as
	select *
	from output.EarliestRxNlAll
	where patid not in (select patid from ExcludeMulti);
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
		   baseline_dt,
		   drugsubstancename,
		   regstartdate
	from EarliestRxNl_Filtered
	group by patid, exposure
	having duration = max(duration)
	;
quit;

/**************************************************************************/
/* STEP 7: Exclude if washout period is less than 365 days                */
/**************************************************************************/

PROC SQL;
create table EarliestRx_washout AS
select * 
from EarliestRxNl_Filtered
having earliest_rx_date - regstartdate > 365;
quit;


/**************************************************************************/
/* STEP 8: Exclude if aSAH occurred before Rx                             */
/**************************************************************************/

proc sql;
CREATE TABLE EarliestRx_aSah_Exclusion AS
SELECT d1.*, d2.patid, d2.aSAH_gp_dt
FROM EarliestRx_washout as d1
INNER JOIN output.nl_cohort as d2 
ON d1.patid = d2.patid
	WHERE d2.aSAH_gp_dt > earliest_rx_date or d2.aSAH_gp_dt is NULL;
quit;


/**************************************************************************/
/* STEP 9: Keep only the same drug as earliest for final prescription set */
/**************************************************************************/

proc sql;
	create table output.NlIndexDrug as
	select p.*
	from output.Rx_PostStart p
		inner join EarliestRx_aSah_Exclusion e
		on p.patid = e.patid
	where p.exposure = e.exposure
	  and p.issuedate >= e.earliest_rx_date
	order by p.patid, p.issuedate;
quit;

*** Link to ATC codes ***;

proc sql;
	create table output.NlDrugAtc_2 as
	select b.*, a.ATC
	from output.NlIndexDrug b
		left outer join rawdata.product_aurum_atc as a
		on b.prodcodeid = a.prodcodeid;
quit;

proc sort data = output.NlDrugAtc_2;
by duration;
run;

proc datasets library=work kill nolist;
run;
quit;

*** THIRD FILE ***;

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
		rawdata.drugissue_3 AS med
	INNER JOIN
		codelist.bph_drugs_fixed AS bphcod
		ON med.ProdCodeId = bphcod.ProdCodeId
	WHERE bphcod.drugsubstancename = "Tamsulosin";
quit;


/****************************************************************************/
/* STEP 2: Clean duration and calculate dose variables                      */
/****************************************************************************/

data nl_tam_cleaning1;
set output.nl_drugs;
if quantity < 1 AND duration < 7 then duration = 1;
else if quantity >= 1 AND duration < 7 then duration = quantity;
else if duration > 365 then duration = 28;
else duration = duration;
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
	FROM nl_tam_cleaning4 AS T
	LEFT OUTER JOIN output.nl_cohort AS BC ON BC.patid = T.patid
ORDER BY T.patid, T.issuedate; 
quit;


/**************************************************************************/
/* STEP 3: Exclude 'PrevalentUsers'                                       */
/**************************************************************************/

proc sql;
	create table PrevalentUsers as
	select distinct d1.patid
	from output.nl_cohort d1
		inner join nl_tam d2
		on d1.patid = d2.patid
	where d2.issuedate between intnx('year', d1.baseline_dt, -1) and d1.baseline_dt - 1;
quit;

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
	and d2.issuedate >= d1.baseline_dt;
quit;


/**************************************************************************/
/* STEP 4: Identify earliest prescription date for each patient           */
/**************************************************************************/

proc sql;
	create table output.NlEarliestDate as
	select patid,
		   min(issuedate) as earliest_rx_date format = ddmmyy10.
	from output.Rx_PostStart
	group by patid;
quit;

proc sql;
	create table output.EarliestRxNlAll as
	select p.patid,
		   p.exposure,
		   p.issuedate,
		   p.duration,
		   p.prodcodeid,
		   p.nl_dt,
		   p.baseline_dt,
		   e.earliest_rx_date,
		   p.regstartdate,
		   p.drugsubstancename
	from output.Rx_PostStart as p
		inner join output.NlEarliestDate as e
		on p.patid = e.patid
	where p.issuedate = e.earliest_rx_date;
quit;


/**************************************************************************/
/* STEP 5: Exclude patients who have more than one record on earliest Rx  */
/**************************************************************************/

proc sql;
	create table ExcludeMulti as
	select patid
	from output.EarliestRxNlAll
	group by patid
	having count(distinct exposure) > 1
	;
quit;

proc sql;
	create table EarliestRxNl_Filtered as
	select *
	from output.EarliestRxNlAll
	where patid not in (select patid from ExcludeMulti);
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
		   baseline_dt,
		   drugsubstancename,
		   regstartdate
	from EarliestRxNl_Filtered
	group by patid, exposure
	having duration = max(duration)
	;
quit;

/**************************************************************************/
/* STEP 7: Exclude if washout period is less than 365 days                */
/**************************************************************************/

PROC SQL;
create table EarliestRx_washout AS
select * 
from EarliestRxNl_Filtered
having earliest_rx_date - regstartdate > 365;
quit;


/**************************************************************************/
/* STEP 8: Exclude if aSAH occurred before Rx                             */
/**************************************************************************/

proc sql;
CREATE TABLE EarliestRx_aSah_Exclusion AS
SELECT d1.*, d2.patid, d2.aSAH_gp_dt
FROM EarliestRx_washout as d1
INNER JOIN output.nl_cohort as d2 
ON d1.patid = d2.patid
	WHERE d2.aSAH_gp_dt > earliest_rx_date or d2.aSAH_gp_dt is NULL;
quit;


/**************************************************************************/
/* STEP 9: Keep only the same drug as earliest for final prescription set */
/**************************************************************************/

proc sql;
	create table output.NlIndexDrug as
	select p.*
	from output.Rx_PostStart p
		inner join EarliestRx_aSah_Exclusion e
		on p.patid = e.patid
	where p.exposure = e.exposure
	  and p.issuedate >= e.earliest_rx_date
	order by p.patid, p.issuedate;
quit;

*** Link to ATC codes ***;

proc sql;
	create table output.NlDrugAtc_3 as
	select b.*, a.ATC
	from output.NlIndexDrug b
		left outer join rawdata.product_aurum_atc as a
		on b.prodcodeid = a.prodcodeid;
quit;

proc sort data = output.NlDrugAtc_3;
by duration;
run;

proc datasets library=work kill nolist;
run;
quit;

*** FOURTH FILE ***;

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
		rawdata.drugissue_4 AS med
	INNER JOIN
		codelist.bph_drugs_fixed AS bphcod
		ON med.ProdCodeId = bphcod.ProdCodeId
	WHERE bphcod.drugsubstancename = "Tamsulosin";
quit;


/****************************************************************************/
/* STEP 2: Clean duration and calculate dose variables                      */
/****************************************************************************/

data nl_tam_cleaning1;
set output.nl_drugs;
if quantity < 1 AND duration < 7 then duration = 1;
else if quantity >= 1 AND duration < 7 then duration = quantity;
else if duration > 365 then duration = 30;
else duration = duration;
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
	FROM nl_tam_cleaning4 AS T
	LEFT OUTER JOIN output.nl_cohort AS BC ON BC.patid = T.patid
ORDER BY T.patid, T.issuedate; 
quit;


/**************************************************************************/
/* STEP 3: Exclude 'PrevalentUsers'                                       */
/**************************************************************************/

proc sql;
	create table PrevalentUsers as
	select distinct d1.patid
	from output.nl_cohort d1
		inner join nl_tam d2
		on d1.patid = d2.patid
	where d2.issuedate between intnx('year', d1.baseline_dt, -1) and d1.baseline_dt - 1;
quit;

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
	and d2.issuedate >= d1.baseline_dt;
quit;


/**************************************************************************/
/* STEP 4: Identify earliest prescription date for each patient           */
/**************************************************************************/

proc sql;
	create table output.NlEarliestDate as
	select patid,
		   min(issuedate) as earliest_rx_date format = ddmmyy10.
	from output.Rx_PostStart
	group by patid;
quit;

proc sql;
	create table output.EarliestRxNlAll as
	select p.patid,
		   p.exposure,
		   p.issuedate,
		   p.duration,
		   p.prodcodeid,
		   p.nl_dt,
		   p.baseline_dt,
		   e.earliest_rx_date,
		   p.regstartdate,
		   p.drugsubstancename
	from output.Rx_PostStart as p
		inner join output.NlEarliestDate as e
		on p.patid = e.patid
	where p.issuedate = e.earliest_rx_date;
quit;


/**************************************************************************/
/* STEP 5: Exclude patients who have more than one record on earliest Rx  */
/**************************************************************************/

proc sql;
	create table ExcludeMulti as
	select patid
	from output.EarliestRxNlAll
	group by patid
	having count(distinct exposure) > 1
	;
quit;

proc sql;
	create table EarliestRxNl_Filtered as
	select *
	from output.EarliestRxNlAll
	where patid not in (select patid from ExcludeMulti);
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
		   baseline_dt,
		   drugsubstancename,
		   regstartdate
	from EarliestRxNl_Filtered
	group by patid, exposure
	having duration = max(duration)
	;
quit;

/**************************************************************************/
/* STEP 7: Exclude if washout period is less than 365 days                */
/**************************************************************************/

PROC SQL;
create table EarliestRx_washout AS
select * 
from EarliestRxNl_Filtered
having earliest_rx_date - regstartdate > 365;
quit;


/**************************************************************************/
/* STEP 8: Exclude if aSAH occurred before Rx                             */
/**************************************************************************/

proc sql;
CREATE TABLE EarliestRx_aSah_Exclusion AS
SELECT d1.*, d2.patid, d2.aSAH_gp_dt
FROM EarliestRx_washout as d1
INNER JOIN output.nl_cohort as d2 
ON d1.patid = d2.patid
	WHERE d2.aSAH_gp_dt > earliest_rx_date or d2.aSAH_gp_dt is NULL;
quit;


/**************************************************************************/
/* STEP 9: Keep only the same drug as earliest for final prescription set */
/**************************************************************************/

proc sql;
	create table output.NlIndexDrug as
	select p.*
	from output.Rx_PostStart p
		inner join EarliestRx_aSah_Exclusion e
		on p.patid = e.patid
	where p.exposure = e.exposure
	  and p.issuedate >= e.earliest_rx_date
	order by p.patid, p.issuedate;
 
*** Link to ATC codes ***;

proc sql;
	create table output.NlDrugAtc_4 as
	select b.*, a.ATC
	from output.NlIndexDrug b
		left outer join rawdata.product_aurum_atc as a
		on b.prodcodeid = a.prodcodeid;
quit;

proc sort data = output.NlDrugAtc_4;
by duration;
run;


/**************************************************************************/
/* STEP 10: COMBINE FILES */
/**************************************************************************/

data output.all_nl_drugissue;
set output.nldrugatc_1
output.nldrugatc_2
output.nldrugatc_3
output.nldrugatc_4;
run;

proc sort data = output.all_nl_drugissue;
by duration patid issuedate;
run;


*** testing implausible end of follow-up dates ***;
data test;
set output.all_nl_drugissue;
daysdiff = nl_dt - regstartdate;
sickbeforereg = 0;
if daysdiff < 0 then sickbeforereg = 1;
run;

proc freq data = test;
tables sickbeforereg /missing;
run;


