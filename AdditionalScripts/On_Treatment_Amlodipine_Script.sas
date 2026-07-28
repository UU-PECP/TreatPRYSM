
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
  create table output.amlodipine_ot as
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
	from output.amlodipine_ot
	group by index_exposure;
quit;

*************************************************************************************************************************;
/* 3. OT: GENERATE MOST RECENT BMI VALUE BEFORE OR ON EACH INTERVAL_WINDOW_START (i.e time-varying) */
*************************************************************************************************************************;

proc sql;
   create table work.bmi_latest_ot as
   select  o.patid,
           o.interval_window_start,
           max(b.bmidate)  as bmi_recent_date         /* latest BMI date before window_start*/
   from    output.amlodipine_ot   as o
   left join
           output.bmi_all         as b
     on    o.patid  = b.patid
    and    b.bmidate <= o.interval_window_start
   group by o.patid,
            o.interval_window_start;
quit;

proc sql;
   create table output.amlodipine_ot_bmi as
   select  o.*                                   /* all original variables   */                
         , b.bmi        as bmi_value
   from   output.amlodipine_ot   as o            /* original interval table  */
   left join work.bmi_latest_ot  as l
          on  o.patid                = l.patid
          and o.interval_window_start = l.interval_window_start
   left join output.bmi_all       as b
          on  l.patid          = b.patid
          and l.bmi_recent_date = b.bmidate
   order by o.patid,
            o.interval_window_start;
quit;





*************************************************************************************************************************;
/* 3. OT: GENERATE MOST RECENT SMK VALUE BEFORE OR ON EACH INTERVAL_WINDOW_START (i.e time-varying) */
*************************************************************************************************************************;


proc sql;
   create table work.smk_latest_ot as
   select  o.patid,
           o.interval_window_start,
           max(b.eventdate)  as smk_recent_date
   from    output.amlodipine_ot_bmi   as o
   left join
           work.smk_unique         as b
     on    o.patid  = b.patid
    and    b.eventdate <= o.interval_window_start
   group by o.patid,
            o.interval_window_start;
quit;

proc sql;
   create table output.amlodipine_ot_bmi_smk as
   select  o.*                                   /* all original variables   */                
         , COALESCE(b.smk_status, 'UNKNOWN') AS smk_status
   from   output.amlodipine_ot_bmi   as o            /* original interval table  */
   left join work.smk_latest_ot  as l
          on  o.patid                = l.patid
          and o.interval_window_start = l.interval_window_start
   left join work.smk_unique       as b
          on  l.patid          = b.patid
          and l.smk_recent_date = b.eventdate
   order by o.patid,
            o.interval_window_start;
quit;
