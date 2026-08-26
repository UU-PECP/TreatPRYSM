
/**************************************************************************/
/*  Treat-PRYSM - Tamsulosin and aSAH risk                                */
/*  File 7.2: Time-varying BMI & smoking for ON-TREATMENT analysis (BPH)  */
/*                                                                          */
/*  Adds most-recent-on-or-before-interval BMI and smoking to output.bph_ot */
/*  (the interval-level table from File 7.1). Same recency logic as Jos's  */
/*  amlodipine OT script, but minor changes for CPRD aurum column names:   */
/*    - BMI:      output.bmi_all,     date = obsdate, value = BMI_final    */
/*    - Smoking:  output.smoking_all, date = obsdate, flags = smk_cur/ex/non */
/**************************************************************************/

libname output "F:\Users\Wyatt003\BPH_nephrolithiasis\Output";
options fullstimer;

%LET inputfile = output.test_ot;

/**************************************************************************/
/* Dedupe BMI to one row per patient+obsdate (keep highest BMI on a day)   */
/* Mirrors the same-day handling used in the per-protocol combine (3_4).   */
/**************************************************************************/
proc sort data = output.bmi_all out = bmi_dedup;
	by patid obsdate descending BMI_final;
run;

data bmi_dedup;
	set bmi_dedup;
	by patid obsdate;
	if first.obsdate;
run;


/**************************************************************************/
/* BMI: most recent value on or before each interval_window_start          */
/**************************************************************************/
proc sql;
	create table work.bmi_latest_ot as
	select o.patid,
	       o.interval_window_start,
	       max(b.obsdate) as bmi_recent_date format=date9.   /* latest BMI date <= window start */
	from &inputfile as o
	     left join bmi_dedup as b
	       on o.patid = b.patid
	      and b.obsdate <= o.interval_window_start
	group by o.patid, o.interval_window_start;
quit;

proc sql;
	create table output.bph_ot_bmi as
	select o.*,
	       b.BMI_final as bmi_value
	from &inputfile as o
	     left join work.bmi_latest_ot as l
	       on o.patid = l.patid
	      and o.interval_window_start = l.interval_window_start
	     left join bmi_dedup as b
	       on l.patid = b.patid
	      and l.bmi_recent_date = b.obsdate
	order by o.patid, o.interval_window_start;
quit;


/**************************************************************************/
/* Dedupe smoking to one row per patient+obsdate (keep 'current' on ties)  */
/* Mirrors the per-protocol combine (3_4) which sorted descending smk_cur. */
/**************************************************************************/
proc sort data = output.smoking_all out = smk_dedup;
	by patid obsdate descending smk_cur;
run;

data smk_dedup;
	set smk_dedup;
	by patid obsdate;
	if first.obsdate;
run;


/**************************************************************************/
/* Smoking: most recent status on or before each interval_window_start     */
/**************************************************************************/
proc sql;
	create table work.smk_latest_ot as
	select o.patid,
	       o.interval_window_start,
	       max(b.obsdate) as smk_recent_date format=date9.
	from output.bph_ot_bmi as o
	     left join smk_dedup as b
	       on o.patid = b.patid
	      and b.obsdate <= o.interval_window_start
	group by o.patid, o.interval_window_start;
quit;

proc sql;
	create table output.bph_ot_bmi_smk as
	select o.*,
	       b.smk_cur,
	       b.smk_ex,
	       b.smk_non
	from output.bph_ot_bmi as o
	     left join work.smk_latest_ot as l
	       on o.patid = l.patid
	      and o.interval_window_start = l.interval_window_start
	     left join smk_dedup as b
	       on l.patid = b.patid
	      and l.smk_recent_date = b.obsdate
	order by o.patid, o.interval_window_start;
quit;


/**************************************************************************/
/* Set smoking-missing intervals to a clean 'unknown' (all flags 0)        */
/* (a patient/interval with no prior smoking record before window start)   */
/**************************************************************************/
data output.bph_ot_bmi_smk;
	set output.bph_ot_bmi_smk;
	if missing(smk_cur) then smk_cur = 0;
	if missing(smk_ex)  then smk_ex  = 0;
	if missing(smk_non) then smk_non = 0;
	if smk_cur = 0 and smk_ex = 0 and smk_non = 0 then smk_unknown = 1;
	else smk_unknown = 0;
run;

/**************************************************************************/
/* Age at episode start   */
/**************************************************************************/


proc sql;
create table output.bph_ot_bmi_smk_age as
select ot.*, year(ot.interval_window_start) - bc.yob as age_at_interval_start
from output.bph_ot_bmi_smk as ot
left join output.bph_cohort as bc 
on ot.patid = bc.patid;
quit;


