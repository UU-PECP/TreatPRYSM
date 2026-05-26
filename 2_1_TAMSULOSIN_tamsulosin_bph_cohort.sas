/**************************************************************************/
/* Set up library references and global options                           */
/**************************************************************************/

libname rawdata "F:\Users\Wyatt003\BPH_nephrolithiasis\SAS";
libname output "F:\Users\Wyatt003\BPH_nephrolithiasis\Output";
libname codelist "C:\Users\Wyatt003\OneDrive - Universiteit Utrecht\Documents\Codelists\3_MagdasCodes";

options fullstimer; /* Display detailed resource usage info in log */




/* This was my workaround for import errors    */
proc import datafile = 'C:\Users\Wyatt003\OneDrive - Universiteit Utrecht\Documents\Scripts\DRUGCODELIST_COHORT1_BPH_with_active_substance_and_mg.txt'
	out=output.bphdrugs_codelist
	dbms=dlm
	replace;
	delimiter='09'x;
	getnames=yes;
run;



/* this is my workaround for when the files weren't being read properly, maybe I delete it later */

data output.tamsulosin;
	set rawdata.drugissue_1;
	where prodcodeid in ("1406241000033110", "3342941000033112", "5632441000033119", "8960641000033119", "9201141000033115", "11524441000033118");
	run;

	data output.alfuzosin;
	set rawdata.drugissue_1;
	where prodcodeid in ("3541000033112", "420309110000001107", "20775410000033111");
	run;

	data output.finasteride;
	set rawdata.drugissue_1;
	where prodcodeid in ("576641000033110", "2724041000033113", "13956641000033113");
	run; 


	/*Jos original trying with Magda's codelists */

	proc sql;
	CREATE TABLE output.new_bph_cohort AS
	SELECT med.patid, 
		   med.issuedate,
		   med.quantity, 
		   med.dosageid, 
		   bphcod.exposure,
		   bphcod.drugsubstancename,
		   bphcod.mg_value
	FROM 
		rawdata.drugissue_1 AS med
	INNER JOIN
		codelist.bph AS bphcod
		ON med.prodcode = strip(put(amlcod.prodcode, best12.))
	WHERE med.qty > 0;
quit;
/**************************************************************************/
/* STEP 4: Subset data to only include valid prescriptions                */
/*         (merging with base_cohort and applying study-end restriction 
			and quantity of at least 1)                                   */
/**************************************************************************/
/* 1) Join with base_cohort so only patients in our main cohort remain.   */
/* 2) Only keep prescriptions before March 31, 2023.                      */
PROC SQL;
CREATE TABLE bph_tam AS
	SELECT T.patid, T.issueid, T.probobsid, T.drugrecid, T.issuedate, T.prodcodeid, T.dosageid, T.quantity, T.duration
	FROM output.tamsulosin AS T
	INNER JOIN output.bph_cohort AS BC ON BC.patid = T.patid
	WHERE T.issuedate > MDY(31,10,2002) and T.issuedate < MDY(03,31,2026) and T.quantity > 0 
ORDER BY T.patid, T.issuedate; 
quit;

proc contents data = bph_tam;
run;

proc contents data = output.bph_cohort;
run;

proc contents data = common_dosages;
run;


/**************************************************************************/
/* STEP 6: Add daily dosage information                                  */
/**************************************************************************/
/* 1) Left-join with common_dosages to retrieve typical daily dose.       */          
/* 2) Calculate 'treatment_duration' = quantity / daily_dose.             */
/* 3) 'mean_daily_dose' = mg_value * daily_dose (dose strength * freq).   */
/*			NOTE: There is only one prescribe mg value of tamsulosin in   */
/*			CPRD Aurum, 400mg dosages are then written as capsules in 	  */
/*			common dosages												  */
/* 4) We assume missing values correspond to 							  
	  1 pill a day (based on empirical observation, and that 0 pills a day
	  correspond to as needed, and set to 0.5 a day                       */;

proc sort data = bph_tam;
by dosageid;
run;

proc sort data = common_dosages;
by dosageid;
run;

data bph_tam_dose;
merge common_dosages (in=x) bph_tam (in=y);
by dosageid;
if x and y;
run;

proc contents data = bph_tam_dose;
run;

data bph_tam_dose;
set bph_tam_dose;
mg_dose = 0.4;
run;



proc sql;
	create table bph_tam_dose as
	select * ,
		   quantity / CASE 
						WHEN daily_dose IS NULL THEN 1 
						WHEN daily_dose = 0 THEN 0.5 
						ELSE daily_dose 
					END AS treatment_duration,
		   mg_dose * CASE 
							WHEN daily_dose IS NULL THEN 1 
							WHEN daily_dose = 0 THEN 0.5 
							ELSE daily_dose 
						END AS mean_daily_dose
	from bph_tam_dose
	ORDER BY patid, issuedate;
quit;

proc contents data = bph_tam_dose;
run;

/**************************************************************************/
/* Quick check: Count unique patients in the Lisinopril cohort            */
/**************************************************************************/
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


/**************************************************************************/
/* STEP 6: Create 'PrevalentUsers' dataset                                */
/**************************************************************************/
/* 'Prevalent users' are those who had a drug prescription X years before   */
/* their baseline date. We identify them by comparing eventdate with the  */
/* baseline_dt in base_cohort. */

%let years = 1; /* Define the number of years for look-back */

proc sql;
	create table PrevalentUsers as
	select distinct d1.patid
	from output.linked_bph d1
		inner join bph_tam_dose d2
		on d1.patid = d2.patid
	where d2.issuedate between intnx('year', d1.baseline_dt, -&years) and d1.baseline_dt - 1;
quit;

/**************************************************************************/
/* STEP 7: Exclude prevalent users and keep only Rx on/after the baseline */
/**************************************************************************/
/* 1) We remove those in PrevalentUsers.                                  */
/* 2) We only keep prescriptions dated on or after baseline.             */
proc sql;
	create table Rx_PostStart as
	select d1.*,
		   d2.prodcodeid,
		   d2.issuedate,
		   d2.treatment_duration,
		   d2.mean_daily_dose
	from output.linked_bph d1
		inner join bph_tam_dose d2
		on d1.patid = d2.patid
	where not exists (
		select 1
		from PrevalentUsers p
		where p.patid = d1.patid
		)
	and d2.issuedate >= d1.baseline_dt
	;
quit;
* replaced varaible d2.exposure with dr.prodcodeid, not sure if that is important;
/* Check how many unique patients remain after exclusion of prevalent. */
title "Numbers of unique ids after excluding prevalent users";
proc sql;
  select count(distinct patid) as n_patid
  from Rx_PostStart;
quit;
*40 thousand is a really low number... are we sure? ;

/**************************************************************************/
/* STEP 8: Identify earliest prescription date for each patient           */
/**************************************************************************/
/* Finds the minimum (earliest) eventdate among the valid prescriptions.  */
proc sql;
	create table EarliestDate as
	select patid,
		   min(issuedate) as earliest_rx_date
	from Rx_PostStart
	group by patid
	;
quit;

/**************************************************************************/
/* STEP 9: Merge back to keep the row(s) that match earliest date         */
/**************************************************************************/
/* 1) We only keep rows where eventdate = earliest_rx_date.               */
/* 2) We call this 'EarliestRxAll'.                                       */
/* 3) If multiple rows share the same earliest date for a patient, we     */
/*    handle that in the subsequent step.                                 */
proc sql;
	create table output.EarliestRxAll as
	select p.patid,
		   p.prodcodeid,
		   p.issuedate,
		   p.treatment_duration,
		   e.earliest_rx_date
	from Rx_PostStart p
		inner join EarliestDate e
		on p.patid = e.patid
	where p.issuedate = e.earliest_rx_date
	;
quit;

/**************************************************************************/
/* STEP 10: Exclude patients who have more than one record on earliest Rx */
/**************************************************************************/
/* If a patient has >1 row on the earliest date (possibly multiple drugs), */
/* we remove them so each patient has exactly one earliest Rx.            */
proc sql;
	create table output.ExcludeMulti as
	select patid
	from output.EarliestRxAll
	group by patid
	having count(distinct prodcodeid) > 1  /* More than 1 unique exposure => Exclude */
	;
quit;

/* WE ARE HERE */
/* SO IT TURNS OUT DEFINITION OF EXPOSURE MATTERS AFTER ALL */
/* I THINK I NEED TO GET THE MAGDA TO TRANSFORM THE CODELISTS TO HAVE THIS INFORMATION APPROPRIATELY */

/* Check for ties in earliest date */
proc sql;
  select count(distinct patid) as n_excluded
  from output.ExcludeMulti;
quit;

proc sql;
	create table output.EarliestRx_Filtered as
	select *
	from output.EarliestRxAll
	where patid not in (select patid from output.ExcludeMulti);
quit;

proc sql;
	create table output.EarliestRx_SingleDrug as
	select distinct
	       patid, 
		   exposure, 
		   earliest_rx_date, 
		   treatment_duration
	from output.EarliestRx_Filtered
	group by patid, exposure
	having treatment_duration = max(treatment_duration)  /* Prefer longest treatment if two prescriptions on same date */
	;
quit;


/**************************************************************************/
/* STEP 11: Merge the single earliest Rx info with base_cohort            */
/**************************************************************************/
/* Add baseline info from base_cohort, creating 'EarliestRx_SingleDrug2'. */
proc sql;
	create table output.EarliestRx_SingleDrug2 as
	select e.*,
		   d1.*
	from output.EarliestRx_SingleDrug e
		inner join output.base_cohort d1
		on e.patid = d1.patid
	;
quit;

/**************************************************************************/
/* Check the differences in gp based and icp based definitions of aSAH    */
/**************************************************************************/

proc sql;
	create table output.test as
	select * from output.EarliestRx_SingleDrug2
	where first_asah_dt IS NOT NULL
	;

proc sql;
	create table output.test2 as
	select * from output.test
	where aSAH_hosp_dt IS NULL AND aSAH_gp_dt IS NOT NULL
	;

proc sql;
	select * from rawdata.clinical
	WHERE patid in ('1022210525', '1039310321', '1068510359', '108910016', '1137410043')
	ORDER BY patid, aSAH_dt;

proc sql;
	select * from output.hes_diagnosis_hosp
	WHERE patid in (1022210525,1039310321,1068510359,108910016,1137410043)
	ORDER BY patid, hosp.admidate;

/**************************************************************************/
/* STEP 12: Exclude if subarachnoid hemorrhage (aSAH) occurred before Rx  */
/**************************************************************************/
/* OUTDATED (Based on both GP and Hosp): If a patient’s first aSAH date (either GP or hosp) is before earliest Rx, we drop them.    */

*/ data output.EarliestRx_SingleDrug2; */
*/	set output.EarliestRx_SingleDrug2;
*/	first_asah_dt = min(asah_gp_dt, asah_hosp_dt);
*/
*/	/* If aSAH is before the earliest prescription date, remove them */
*/	if not missing(first_asah_dt) and first_asah_dt < earliest_rx_date then delete;
*/ run;

/* If a patient’s first aSAH date (HOSP ONLY) is before earliest Rx, we drop them.    */
data output.EarliestRx_SingleDrug2;
	set output.EarliestRx_SingleDrug2;
	first_asah_dt = min(asah_hosp_dt);

	/* If aSAH is before the earliest prescription date, remove them */
	if not missing(first_asah_dt) and first_asah_dt < earliest_rx_date then delete;
run;


/**************************************************************************/
/* STEP 13: Keep only the same drug as earliest for final prescription set*/
/**************************************************************************/
/* 1) We bring back all prescriptions from Rx_PostStart that match the    */
/*    same exposure name and occur after earliest Rx date for that patid. */
/* 2) This will be used for bridging (continuous coverage) analysis.      */
proc sql;
	create table output.AllIndexDrug as
	select p.*
	from output.Rx_PostStart p
		inner join output.EarliestRx_SingleDrug2 e
		on p.patid = e.patid
	where p.exposure = e.exposure
	  and p.eventdate >= e.earliest_rx_date
	order by p.patid, p.eventdate;
quit;

/**************************************************************************/
/* STEP 14: Use a bridging algorithm to combine Rx coverage blocks        */
/**************************************************************************/
/* 1) bridged_period_id increments whenever there is a days_between_prescriptions > gap_days.    */
/* 2) If the days_between_prescriptions is <= gap_days, we consider it the same coverage block.  */
/* 3) bridged_coverage_start = eventdate of first prescription in a block.        */
/* 4) bridged_coverage_end   = last prescription's end date.                      */
%let gap_days = 30; /* grace period */

data output.BridgeCoverage;
	set output.AllIndexDrug;
	by patid;
	
	/* expected_rx_end_date = eventdate + (treatment_duration - 1) => coverage end date */
	expected_rx_end_date = eventdate + (treatment_duration - 1);

	retain bridged_coverage_start bridged_coverage_end bridged_period_id;

	if first.patid then do;
		bridged_period_id = 1;
		bridged_coverage_start = eventdate;
		bridged_coverage_end = expected_rx_end_date;
	end;
	else do;
		days_between_prescriptions = eventdate - bridged_coverage_end - 1;
		if days_between_prescriptions <= &gap_days then do;
			/* Extend the bridged_coverage_end if new Rx goes beyond current bridged_coverage_end */
			if expected_rx_end_date > bridged_coverage_end then bridged_coverage_end = expected_rx_end_date;
		end;
		else do;
			/* coverage ended before this new fill => finalize old block and start a new one */
			output;
			bridged_period_id + 1;
			bridged_coverage_start = eventdate;
			bridged_coverage_end = expected_rx_end_date;
		end;
	end;
	if last.patid then output;

	format bridged_coverage_start bridged_coverage_end expected_rx_end_date date9.;
run;

/**************************************************************************/
/* STEP 15: Keep only the first coverage block for per-protocol analysis  */
/**************************************************************************/
/* For a strict per-protocol analysis, we only use bridged_period_id=1.   */
proc sort data = output.BridgeCoverage;
	by patid bridged_period_id;
run;

data output.BridgeCoverage;
    set output.BridgeCoverage;
    end_of_treatment = bridged_coverage_end + &gap_days; /* Adding grace_period */
    format end_of_treatment date9.; /* Ensure date format */
run;

proc sql;
  select count(*) as n_blocks, count(distinct patid) as n_patids
  from output.BridgeCoverage;
quit;

data output.FirstCoverageBlock;
	set output.BridgeCoverage;
	by patid;
	if first.patid; /* first row => bridged_period_id=1 */
run;


/*check bridging on a few patients */

proc sql;
	create table output.test as
	select *
	from output.AllIndexDrug
	where patid in ('1000010203', '1000010379', '1000010515', '1000010567', '100010106')
	order by patid, eventdate;
quit;

proc sql;
	create table output.test2 as
	select *
	from output.BridgeCoverage
	where patid in ('1000010203', '1000010379', '1000010515', '1000010567', '100010106')
	order by patid, bridged_period_id;
quit;

/**************************************************************************/
/* STEP 16: Combine coverage block info with base_cohort => final PP set  */
/**************************************************************************/
/* 1) index_date = bridged_coverage_start                                          */
/* 2) We also bring in relevant baseline data from base_cohort.           */
proc sql;
	create table output.AnalysisSetPP as
	select f.patid,
		   e.exposure,
		   f.bridged_coverage_start as index_date,
		   f.end_of_treatment,
		   d1.*
	from output.FirstCoverageBlock f
		inner join output.EarliestRx_SingleDrug2 e
			on f.patid = e.patid
		inner join output.base_cohort d1
			on f.patid = d1.patid
			;
quit;

/**************************************************************************/
/* STEP 17: Apply end-of-follow-up rules => create final PP dataset       */
/**************************************************************************/
/* 1) end_of_fu = min(end_of_treatment, deathdate, aSAH_hosp_dt, etc.)    				  */
/* 2) Exclude those whose index_date is after any of these end dates i.e. negative fu     */
/* 3) aSAH=1 if aSAH_hosp_dt is end of follow-up.*/

%let END_OF_STUDY = '31MAR2021'd;

data output.bph_pp;
	set output.AnalysisSetPP;

	end_of_fu = end_of_treatment;
	if not missing(tod) and tod < end_of_fu then end_of_fu = tod;
	if not missing(deathdate) and deathdate < end_of_fu then end_of_fu = deathdate;
	if not missing(aSAH_hosp_dt) and aSAH_hosp_dt < end_of_fu then end_of_fu = aSAH_hosp_dt;
	if not missing(lcd) and lcd < end_of_fu then end_of_fu = lcd;
	if &END_OF_STUDY < end_of_fu then end_of_fu =  &END_OF_STUDY;

	if not missing(aSAH_hosp_dt) and aSAH_hosp_dt <= end_of_fu then aSAH=1; else aSAH=0;

	fu_days = end_of_fu - index_date + 1;

	/* Exclude invalid follow-up (where end_of_fu <= index_date) */
	if fu_days > 0;

	format end_of_fu date9.;
run;

proc sql;
  select count(*) as n_invalid_fu 
  from output.bph_pp
  where fu_days <= 0;
quit;

/**************************************************************************/
/* STEP 18: Optional checks and basic descriptives                        */
/**************************************************************************/
/* Quick example: Count exposure groups and describe follow-up durations  */
proc sql;
	select 
		exposure,
		count(patid) AS n,
		min(fu_days) AS min_fu_days,
		max(fu_days) AS max_fu_days,
		median(fu_days) AS median_fu_days,
		mean(fu_days) AS mean_fu_days,
		sum(aSAH) AS n_asah_cases,
		100 * (sum(aSAH) / count(patid)) as n_asah_perc
	from output.bph_pp
	group by exposure;
quit;

proc sql;
	select *
	from output.su_pp
	where patid = '1247910211';
quit;

proc sql;
	select *
	from output.su_cohort
	where patid = '1247910211';
quit;

proc sql;
	select *
	FROM output.BridgeCoverage
	where patid = '1247910211';
quit;


/**************************************************************************/
/* ATTEMPT 2															  */
/* STEPS 19–22: ON-TREATMENT ANALYSIS (CENSOR ON SWITCH)                  */
/**************************************************************************/

/**************************************************************************/
/* STEP 19: Determine earliest switch date to the other exposure          */
/**************************************************************************/

/*We already have these tables:
	- Rx_PostStart: All post-baseline prescriptions (both exposures)
	- EarliestRx_SingleDrug2: Contains each patient's index drug from steps 9-10
*/

/* Create a small table that maps each patient to their index exposure */
proc sql;
	create table output.IndexDrugs as
	select patid, exposure as index_exposure
	from output.EarliestRx_SingleDrug2
	;
quit;

/* Identify any prescriptions in Rx_PostStart that have a different exposure than the index exposure.
   The earliest such date per patid is the switch_date. */
proc sql;
	create table output.SwitchDates as
	select r.patid,
		   min(r.eventdate) as switch_date format=date9.
	from output.Rx_PostStart r
		 inner join output.IndexDrugs i
		 on r.patid = i.patid
	where r.exposure ne i.index_exposure
	group by r.patid
	;
quit;

/* Check a few Switchdates manually */

proc sql;
	create table output.test as
	select *
	from output.SwitchDates
	where patid in ('1000710138', '1000910361', '10010062', '10010558', '100110556')
	;
quit;

proc sql;
	create table output.test2 as
	select *
	from output.Rx_PostStart
	where patid in ('1000710138', '1000910361', '10010062', '10010558', '100110556')
	;
quit;



/**************************************************************************/
/* STEP 20: Build an on-treatment follow-up dataset and censor at switch  */
/**************************************************************************/
/* Merges base_cohort with EarliestRx_SingleDrug 2 (which has earliest
	Rx date for the index drug) and apply end-of-study censoring, plus
	additional censoring if switch date is earlier. */

%let END_OF_STUDY = '31MAR2021'd;

data output.OverallFollowup_OnT;
	merge output.EarliestRx_SingleDrug2(in=inE)
		  output.base_cohort(in=inB
			 keep=patid tod deathdate aSAH_hosp_dt lcd)
		  output.SwitchDates(in=inS);
	by patid;
	if inE and inB;

	index_date = earliest_rx_date;
	index_exposure = exposure;
	end_of_fu = &END_OF_STUDY;

	if not missing(tod) and tod < end_of_fu then end_of_fu = tod;
	if not missing(deathdate) and deathdate < end_of_fu then end_of_fu = deathdate;
	if not missing(aSAH_hosp_dt) and aSAH_hosp_dt < end_of_fu then end_of_fu = aSAH_hosp_dt;
	if not missing(lcd) and lcd < end_of_fu then end_of_fu = lcd;

	/* Additional censoring at switch_date if it exists and is earlier */
	if inS and not missing(switch_date) and switch_date < end_of_fu then end_of_fu = switch_date;

	/* Only keep if valid follow-up (index_date < end_of_fu */
	if index_date < end_of_fu;

	format index_date end_of_fu date9.;
run;

/**************************************************************************/
/* STEP 21: Bridge Coverage for the index drug only  */
/**************************************************************************/
/* From Step 13, AllIndexDrug included all prescriptions for the single
   index drug, from earliest Rx date onward. */

%let gap_days = 30;

data output.BridgeCoverage_IndexDrug;
  set output.AllIndexDrug;
  by patid;

  expected_rx_end_date = eventdate + (treatment_duration - 1);
  retain bridged_coverage_start bridged_coverage_end 
	     bridged_period_id;

  if first.patid then do;
    bridged_period_id = 1;
	bridged_coverage_start = eventdate;
	bridged_coverage_end = expected_rx_end_date;
  end;
  else do;
  	days_between_prescriptions = eventdate - bridged_coverage_end - 1;
	if days_between_prescriptions <= &gap_days then do;
	  if expected_rx_end_date > bridged_coverage_end then bridged_coverage_end = expected_rx_end_date;
	end;
    else do;
      output;
	  bridged_period_id + 1;
	  bridged_coverage_start = eventdate;
	  bridged_coverage_end = expected_rx_end_date;
   end;
 end;

 if last.patid then output;

 format bridged_coverage_start bridged_coverage_end expected_rx_end_date date9.;
run;

/**************************************************************************/
/* STEP 22: Create 30-day intervals and classify recency  */
/**************************************************************************/
/* Use OverallFollowup_OnT with switch-based censoring and 
   BridgeCoverage_IndexDrug to define coverage recency. */

/* 22.0: Build 30-days intervals from index_date to end_of_fu */
data output.ThirtyDayIntervals_OnT;
  set output.OverallFollowup_OnT;
  by patid;

  interval_window_start = index_date;
  do while (interval_window_start <= end_of_fu);
  	interval_window_end = min(interval_window_start + 29, end_of_fu);
	output;
	interval_window_start = interval_window_end + 1;
  end;

  format interval_window_start interval_window_end date9.;
run;

/* 22.1: Add mean_daily_dose per interval */
/* 1 ---------  sort prescriptions  ------------------------- */
proc sort data=output.AllIndexDrug
          out=rx_sorted(keep=patid eventdate mean_daily_dose);
  by patid eventdate;
run;

/* 2 ---------  sort 30-day intervals and give the input a temporary
                 variable called EVENTDATE  ---------------------------- */
proc sort data=output.ThirtyDayIntervals_OnT
                 (rename=(interval_window_start = eventdate))   /* ? here */
          out=int_sorted;
  by patid eventdate;
run;

data output.IntervalDose;
  merge rx_sorted(in=inRx)
        int_sorted(in=inInt);
  by patid eventdate;

  retain last_dose;

  if inRx  then last_dose = mean_daily_dose;   /* update on Rx rows */

  if inInt then do;                            /* output interval rows */
      interval_window_start     = eventdate;   /* restore original name */
      mean_daily_dose_current   = last_dose;   /* most-recent dose      */
      output;
  end;

  drop eventdate last_dose;
run;

/* 22.2 Identify last coverage block that begins on or before interval_window_start  */
/* Essentially adds treatment information to the intervals  */
proc sql;
	create table output.IntervalCoverage_OT as
	select i.patid,
		   i.interval_window_start,
		   i.interval_window_end,
		   max(b.bridged_coverage_start) as last_coverage_period_start format=date9.,
		   max(b.bridged_coverage_end)   as last_coverage_period_end   format=date9.
	from output.ThirtyDayIntervals_OnT i
		left join output.BridgeCoverage_IndexDrug b
			on i.patid = b.patid
			and b.bridged_coverage_start <= i.interval_window_start
	group by i.patid, i.interval_window_start, i.interval_window_end
	order by i.patid, i.interval_window_start;
quit;

/* 22.3 Classify user status as Current/Recent/Past  */
data output.Intervals_RecencyOT;
	merge output.IntervalCoverage_OT(in=inI)
	      output.OverallFollowup_OnT(in=inO
			keep = patid index_exposure index_date end_of_fu gender deprivation_decile yob aSAH_hosp_dt);
	by patid;
	if inI and inO;

	if not missing(last_coverage_period_start) then do;
		days_since_last_treatment = interval_window_start - last_coverage_period_end;

		if days_since_last_treatment <= 0 then do;
			treatment_recency_status = 'Current';
		end;
		else if 0 < days_since_last_treatment <= 120 then do;
			treatment_recency_status = 'Recent';
		end;
		else do;
			treatment_recency_status = 'Past';
		end;
	end;
	else do;
		treatment_recency_status = 'Never'; /*should never happen but good to check */
		days_since_last_treatment =.;
	end;

	  /* NEW: days covered since the start of the current bridged coverage period */
  	if treatment_recency_status = 'Current' then
    	days_since_bridge_start = interval_window_start - last_coverage_period_start + 1;
  	else
    	days_since_bridge_start = .;

	/*Flag aSAH if aSAH_hosp_dt occurs within 30day window*/
	if not missing(aSAH_hosp_dt) and
		aSAH_hosp_dt >= interval_window_start and
		aSAH_hosp_dt <= interval_window_end then aSAH_within_interval=1;
	else aSAH_within_interval=0;

	/*Time-varying age*/
	if not missing(yob) then age_at_interval_start = year(interval_window_start) - yob;
	else age_at_interval_start = .;

	fu_days = end_of_fu - index_date + 1;

	format index_date end_of_fu interval_window_start interval_window_end date9.;
run;

proc sql;
  create table output.lisinopril_ot as
  select  r.*,
          case
            when r.treatment_recency_status = 'Current'
            then d.mean_daily_dose_current
            else .
          end as mean_daily_dose_current
  from    output.Intervals_RecencyOT  r        /* your existing step 22.3 */
  left join
          output.IntervalDose         d
    on    r.patid                = d.patid
    and   r.interval_window_start = d.interval_window_start
  ;
quit;

proc sql;
	select 
		index_exposure,
		count(distinct patid) AS n,
		min(fu_days) AS min_fu_days,
		max(fu_days) AS max_fu_days,
		median(fu_days) AS median_fu_days,
		mean(fu_days) AS mean_fu_days,
		sum(aSAH_within_interval) AS n_asah_cases,
		100 * (sum(aSAH_within_interval) / count(distinct patid)) as n_asah_perc
	from output.lisinopril_ot
	group by index_exposure;
quit;


/* Testing*/
/* Step 1: Select 5 random unique patids */
proc sql outobs=5;
    create table output.RandomPatids as
    select distinct patid
    from output.Intervals_RecencyOT2
    order by ranuni(12345); /* Replace seed as needed */
quit;

/* Step 2: Subset output.Intervals_RecencyOT2 */
proc sql;
    create table output.Subset_Intervals as
    select a.patid, a.interval_window_start, interval_window_end, last_coverage_period_start, last_coverage_period_end,
		   index_date, index_exposure,
		   end_of_fu,
		   days_since_last_treatment, treatment_recency_status,
		   mean_daily_dose_current
    from output.Intervals_RecencyOT2 as a
    inner join output.RandomPatids as b
    on a.patid = b.patid
	order by a.patid, interval_window_start;
quit;

/* Step 3: Subset output.AllIndexDrug */
proc sql;
    create table output.Subset_IndexDrug as
    select a.patid, a.active_substance, eventdate, treatment_duration, mean_daily_dose
    from output.AllIndexDrug as a
    inner join output.RandomPatids as b
    on a.patid = b.patid
	order by a.patid, a.eventdate;
quit;

/* Step 4: Print the results for inspection */
title "Subset from Intervals_RecencyOT2";
proc print data=output.Subset_Intervals;
run;

title "Subset from AllIndexDrug";
proc print data=output.Subset_IndexDrug;
run;
