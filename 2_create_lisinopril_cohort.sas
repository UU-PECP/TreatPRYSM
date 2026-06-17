/**************************************************************************/
/* Set up library references and global options                           */
/**************************************************************************/

libname rawdata 'F:\Users\0631736\Raw';
libname output 'F:\Users\0631736\Output';

options fullstimer; /* Display detailed resource usage info in log */


/**************************************************************************/
/* STEP 1: Import dosage lookup tables                                    */
/**************************************************************************/
/* Import a text file containing common dosages for various drugs.       */
/* "delimiter='09'x" indicates TAB-delimited. "getnames=yes" uses the    */
/* first row as variable names.                                          */

proc import datafile = 'F:\Users\0631736\New codelists\common_dosages.txt'
	out=output.common_dosages
	dbms=dlm
	replace;
	delimiter='09'x;
	getnames=yes;
run;

/* Import a text file containing codelists for lisinopril.               */
/* The 'prodcode' and other drug attributes (e.g. exposure group, active substance, mg) are found in this file.      */
proc import datafile = 'F:\Users\0631736\New codelists\lisinopril_and_other_combined_with_active_substance_and_mg.txt'
	out=output.lisinopril_codelist
	dbms=dlm
	replace;
	delimiter='09'x;
	getnames=yes;
run;

/**************************************************************************/
/* STEP 2: View table structures (Optional)                               */
/**************************************************************************/
/* proc sql DESCRIBE TABLE statements simply show the structure of       */
/* the datasets in the log, e.g. variable names, types, lengths.         */
proc sql;
	describe table rawdata.therapy;
	describe table output.lisinopril_codelist;
	describe table output.common_dosages;
quit;


/**************************************************************************/
/* STEP 3: Create initial Lisinopril cohort from therapy data            */
/**************************************************************************/
/* 1) Join therapy data with lisinopril codelist on matching product code */
/* 2) Convert numeric prodcode (in lisinopril_codelist) to character      */
/*    using put(..., best12.) and strip trailing spaces so that it can    */
/*    match the therapy prodcode field in rawdata.therapy.                */
/*    Only allow actual prescriptions (i.e. qty > 0 )                     */
proc sql;
	CREATE TABLE output.lisinopril_cohort AS
	SELECT med.patid, 
		   med.eventdate,
		   med.qty, 
		   med.dosageid, 
		   liscod.exposure,
		   liscod.active_substance,
		   liscod.mg_value
	FROM 
		rawdata.therapy AS med
	INNER JOIN
		output.lisinopril_codelist AS liscod
		ON med.prodcode = strip(put(liscod.prodcode, best12.))
	WHERE med.qty > 0;
quit;

/**************************************************************************/
/* STEP 4: Subset data to only include valid prescriptions               */
/*         (merging with base_cohort and applying study-end restriction)  */
/**************************************************************************/
/* 1) Join with base_cohort so only patients in our main cohort remain.   */
/* 2) Only keep prescriptions before March 31, 2021.                      */
PROC SQL;
CREATE TABLE output.lisinopril_cohort AS
	SELECT LC.*
	FROM output.lisinopril_cohort AS LC
	INNER JOIN output.base_cohort AS BC ON BC.patid = LC.patid
	WHERE LC.eventdate < MDY(3,31,2021)
ORDER BY LC.patid, LC.eventdate; 
quit;

/**************************************************************************/
/* STEP 5: Add daily dosage information                                  */
/**************************************************************************/
/* 1) Left-join with common_dosages to retrieve typical daily dose.       */          
/* 2) Calculate 'treatment_duration' = quantity / daily_dose.             */
/* 3) 'mean_daily_dose' = mg_value * daily_dose (dose strength * freq).   */
/* 4) We assume missing values correspond to 
	  1 pill a day (based on empirical observation, and that 0 pills a day
	  correspond to as needed, and set to 0.5 a day                       */

proc sql;
	create table output.lisinopril_cohort as
	select LC.patid, LC.eventdate, LC.exposure, LC.active_substance, LC.qty, LC.mg_value, 
		   CD.daily_dose, 
		   LC.qty / CASE 
						WHEN CD.daily_dose IS NULL THEN 1 
						WHEN CD.daily_dose = 0 THEN 0.5 
						ELSE CD.daily_dose 
					END AS treatment_duration, /* in days */
		   LC.mg_value * CASE 
							WHEN CD.daily_dose IS NULL THEN 1 
							WHEN CD.daily_dose = 0 THEN 0.5 
							ELSE CD.daily_dose 
						END AS mean_daily_dose
	from output.lisinopril_cohort AS LC
	left outer join output.common_dosages as CD
		on LC.dosageid = CD.dosageid
	ORDER BY LC.patid, LC.eventdate;
quit;

/**************************************************************************/
/* Quick check: Count unique patients in the Lisinopril cohort            */
/**************************************************************************/
title "Numbers of unique ids in lisinopril cohort";
proc sql;
  select count(distinct patid) as n_patid
  from output.lisinopril_cohort;
quit;

/* Check that there are no negative or zero durations */
title "Numbers of people with 0 treatment duration";
proc sql;
  select count(*) as n_zero_treat
  from output.lisinopril_cohort
  where treatment_duration <= 0;
quit;


/* Check the distribution of mean_daily_dose to see if it is plausible (no extremely large or negative values) */
/* Some extreme values (e.g. 5000). Need to correct for this later */
title "Max mean_daily_dose";
proc sql;
  select max(mean_daily_dose)
  from output.lisinopril_cohort;
quit;

proc sql;
  select *
  from output.lisinopril_cohort
  where mean_daily_dose > 1000;
quit;

/**************************************************************************/
/* STEP 6: Create 'PrevalentUsers' dataset                                */
/**************************************************************************/
/* 'Prevalent users' are those who had a lisinopril prescription X years before   */
/* their baseline date. We identify them by comparing eventdate with the  */
/* baseline_dt in base_cohort. */

%let years = 1; /* Define the number of years for look-back */

proc sql;
	create table output.PrevalentUsers as
	select distinct d1.patid
	from output.base_cohort d1
		inner join output.lisinopril_cohort d2
		on d1.patid = d2.patid
	where d2.eventdate between intnx('year', d1.baseline_dt, -&years) and d1.baseline_dt - 1;
quit;

/**************************************************************************/
/* STEP 7: Exclude prevalent users and keep only Rx on/after the baseline */
/**************************************************************************/
/* 1) We remove those in PrevalentUsers.                                  */
/* 2) We only keep prescriptions dated on or after baseline.             */
proc sql;
	create table output.Rx_PostStart as
	select d1.*,
		   d2.exposure,
		   d2.active_substance,
		   d2.eventdate,
		   d2.treatment_duration,
		   d2.mean_daily_dose
	from output.base_cohort d1
		inner join output.lisinopril_cohort d2
		on d1.patid = d2.patid
	where not exists (
		select 1
		from output.PrevalentUsers p
		where p.patid = d1.patid
		)
	and d2.eventdate >= d1.baseline_dt
	;
quit;



/* Check how many unique patients remain before exclusion of prevalent. */
title "Numbers of unique ids before excluding prevalent users";
proc sql;
  select count(distinct patid) as n_patid
  from output.lisinopril_cohort;
quit;

title "Numbers of unique ids after excluding prevalent users";
proc sql;
  select count(distinct patid) as n_patid
  from output.Rx_PostStart;
quit;


/* Check the number of prevalent users. */
title "Numbers of unique ids in prevalent users";
proc sql;
  select count(distinct patid) as n_patid
  from output.PrevalentUsers;
quit;


/**************************************************************************/
/* STEP 8: Identify earliest prescription date for each patient           */
/**************************************************************************/
/* Finds the minimum (earliest) eventdate among the valid prescriptions.  */
proc sql;
	create table output.EarliestDate as
	select patid,
		   min(eventdate) as earliest_rx_date
	from output.Rx_PostStart
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
		   p.exposure,
		   p.eventdate,
		   p.treatment_duration,
		   e.earliest_rx_date
	from output.Rx_PostStart p
		inner join output.EarliestDate e
		on p.patid = e.patid
	where p.eventdate = e.earliest_rx_date
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
	having count(distinct exposure) > 1  /* More than 1 unique exposure => Exclude */
	;
quit;

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

data output.lisinopril_pp;
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
  from output.lisinopril_pp
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
	from output.lisinopril_pp
	group by exposure;
quit;

proc sql;
	select *
	from output.lisinopril_pp
	where patid = '1247910211';
quit;

proc sql;
	select *
	from output.lisinopril_cohort
	where patid = '1247910211';
quit;

proc sql;
	select *
	FROM output.BridgeCoverage
	where patid = '1247910211';
quit;

/* testing */
/* aSAH cases */
/* 104210333  [x]*/
/* 1080410304 [x] bit silly to say end of treatment is august when patient died in may, but end_of_fu and bridging is defined correctly*/
/* 145310380  [x]*/
/* 2493010426 [x]*/
/* 1856810410 [x]*/

/* aSAH after end of FU*/
/* 10010558     [x] Correct since patient switched from OtherACE to lisinopril a few years before developing aSAH*/
/* 101310526    [x] Correct, patient only had a single prescription years before aSAH */
/* 1023310658   [x] Correct, lcd way before aSAH. */
/* 1138410184   [x] Correct, end of treamtnet way before aSAH */
/* 1356110762   [x] Correct, aSAH few months after end of last prescription.. */

/* Randos from lisinopril cohort*/
/* 1019110178 [x] Probably a prevalent user, started using in 1999 */
/* 1019210157 [x] Although a glance suggests a longer treatment coverage. May need to extend the grace period */
/* 1247910211 [x]*/
/* 1442010093 [x] Switcher*/



/**************************************************************************/
/* ATTEMPT 2															  */
/* STEPS 19–22: ON-TREATMENT ANALYSIS (CENSOR ON SWITCH)                  */
/**************************************************************************/

/**************************************************************************/
/* STEP 19: Determine earliest switch date to the other exposure          */
/**************************************************************************/

/*We already have these tables:
	- Rx_PostStart: All post-baseline prescriptions (both exposures)
	- EarliestRx_SIngleDrug2: Contains each patient's index drug from steps 9-10
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
