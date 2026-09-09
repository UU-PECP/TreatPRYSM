
/**************************************************************************/
/*  Treat-PRYSM - Tamsulosin and aSAH risk                                */
/*  File 7.1: ON-TREATMENT ANALYSIS (BPH) - censor on switch              */
/*  Adapted from Jos Kanning's amlodipine on-treatment script             */
/*                                                                          */
/*  KEY DIFFERENCE FROM JOS'S VERSION:                                     	*/
/*  Jos rebuilt bridged coverage in SAS (his Step 21) from AllIndexDrug.   	*/
/*  Our treatment episodes were built in R with AdhereR, so instead we     	*/
/*  import bph_treatmentepisodes.csv and use its episode.start/episode.end 	*/
/*  directly as the coverage blocks (AdhereR already did the bridging).  	*/
/*  Other additions:														*/
/*	- Name changes (eventdate to issue date									*/
/*  - Integration into macro which processes 4 data subset files			*/
/*	- moved covariate creation into file 7_2								*/
/**************************************************************************/

libname rawdata "F:\Users\Wyatt003\BPH_nephrolithiasis\SAS";
libname output "F:\Users\Wyatt003\BPH_nephrolithiasis\Output";
options fullstimer;

/**************************************************************************/
/* STEP 0.0: Import R-generated treatment episodes                          */
/**************************************************************************/
/* Original file by Jos uses a SAS only workflow. This version
/* imports the treatment episodes developed in AdhereR. The outcome of
AdhereR exports a .csv file that then must be imported into SAS */

data output.bph_treatmentepisodes;
	infile "F:\Users\Wyatt003\BPH_nephrolithiasis\Output\bph_treatmentepisodes.csv"
		dsd dlm=',' firstobs=2 truncover;
	length exposure 8 patid $19 episode_ID 8
	       episode_start 8 end_episode_gap_days 8 episode_duration 8 episode_end 8;
	input exposure patid :$19. episode_ID
	      episode_start :yymmdd10. end_episode_gap_days episode_duration episode_end :yymmdd10.;
	format episode_start episode_end date9.;
run;

/**************************************************************************/
/* STEP 1.0: Create mg Value and Mean Daily Dose                          */
/**************************************************************************/

/* Sort both datasets for merge */
proc sort data = output.bph_treatmentepisodes; by patid exposure; run;
proc sort data = output.all_bph_episodes out = rx_sorted(keep = patid exposure issuedate quantity mg_value); 
  by patid exposure issuedate; 
run;

/* Join prescriptions to episodes, keep only those within episode window */
proc sql;
  create table output.episodes_with_qty as
  select e.patid,
         e.exposure,
         e.episode_ID,
         e.episode_start,
         e.episode_end,
         sum(r.quantity) as total_tablets,
		 mean(r.mg_value) as mean_daily_dose
  from output.bph_treatmentepisodes e
       inner join rx_sorted r
       on e.patid = r.patid
       and e.exposure = r.exposure
       and r.issuedate >= e.episode_start
       and r.issuedate <= e.episode_end
  group by e.patid, e.exposure, e.episode_ID, e.episode_start, e.episode_end;
quit;

/* Merge back onto treatment episodes */
proc sort data = output.episodes_with_qty; by patid exposure episode_ID; run;
proc sort data = output.bph_treatmentepisodes; by patid exposure episode_ID; run;

data output.bph_treatmentepisodes_mgqty;
  merge output.bph_treatmentepisodes(in=a)
        output.episodes_with_qty(in=b);
  by patid exposure episode_ID;
  if a;
run;

data output.bph_treatmentepisodes_mgqty;
set output.bph_treatmentepisodes_mgqty;
cumulative_dose = total_tablets*mean_daily_dose;
run;

/**************************************************************************/
/* STEP 1.1: Create end of follow-up variable                             */
/**************************************************************************/

proc sort data = output.bph_cohort;
by patid;
run;

data output.bph_treatmentepisodes_fu;
	merge output.bph_treatmentepisodes_mgqty(in=inA)
		  output.bph_cohort(in=inB
			 keep=patid censordate aSAH_apc_dt);
	by patid;
	if inA and inB;
	index_date = earliest_rx_date;
	index_exposure = exposure;
	end_of_fu = '31MAR2025'd;

	if not missing(censordate) and censordate < end_of_fu then end_of_fu = censordate;
	if not missing(aSAH_apc_dt) and aSAH_apc_dt < end_of_fu then end_of_fu = aSAH_apc_dt;

	/* Additional censoring at switch_date if it exists and is earlier */
	if not missing(episode_end) and episode_end < end_of_fu then end_of_fu = episode_end;

	/* Only keep if valid follow-up (index_date < end_of_fu */
	if index_date < end_of_fu;

	format index_date end_of_fu date9.;
run;

/**************************************************************************/
/* STEP 2.0: Build 30-day intervals from index_date to end_of_fu          */
/**************************************************************************/
data output.ThirtyDayIntervals_OnT;
	set output.bph_treatmentepisodes_fu;
	by patid;

	interval_window_start = episode_start;
	do while (interval_window_start <= end_of_fu);
		interval_window_end = min(interval_window_start + 29, end_of_fu);
		output;
		interval_window_start = interval_window_end + 1;
	end;

	format interval_window_start interval_window_end date9.;
run;


/**************************************************************************/
/* STEP 2.1: Carry most-recent per-Rx dose (mg_value) into each interval  */
/**************************************************************************/
/* mg_value is per-prescription in Rx_bph_PostStart; propagate the most    */
/* recent value forward across intervals (time-varying dose).              */

proc sort data = output.all_bph_episodes
          out  = mg_sorted(keep=patid issuedate mg_value);
	by patid issuedate;
run;

proc sort data = output.ThirtyDayIntervals_OnT
                 (rename=(interval_window_start = issuedate))
          out  = int_sorted;
	by patid issuedate;
run;

data output.IntervalDose;
	merge mg_sorted(in=inRx)
	      int_sorted(in=inInt);
	by patid issuedate;
	retain last_dose;

	if inRx  then last_dose = mg_value;          /* update on Rx rows */
	if inInt then do;                            /* output interval rows */
		interval_window_start   = issuedate;     /* restore original name */
		mg_value_current        = last_dose;     /* most-recent dose */
		output;
	end;
	drop issuedate last_dose;
run;


/**************************************************************************/
/* STEP 2.2: Last coverage block starting on/before interval_window_start */
/**************************************************************************/
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


/**************************************************************************/
/* STEP 2.3: Classify recency (Current/Recent/Past) and flag aSAH        */
/**************************************************************************/
proc sort data = output.IntervalCoverage_OT; by patid; run;

data &out;
	merge output.IntervalCoverage_OT(in=inI)
	      output.OverallFollowup_OnT(in=inO
			keep = patid index_exposure index_date end_of_fu aSAH_apc_dt);
	by patid;
	if inI and inO;

	if not missing(last_coverage_period_start) then do;
		days_since_last_treatment = interval_window_start - last_coverage_period_end;
		if days_since_last_treatment <= 0 then treatment_recency_status = 'Current';
		else if 0 < days_since_last_treatment <= 120 then treatment_recency_status = 'Recent';
		else treatment_recency_status = 'Past';
	end;
	else do;
		treatment_recency_status = 'Never';  /* should not happen; good to check */
		days_since_last_treatment = .;
	end;

	if treatment_recency_status = 'Current' then
		days_since_bridge_start = interval_window_start - last_coverage_period_start + 1;
	else
		days_since_bridge_start = .;

	/* aSAH flag if event falls within this 30-day window */
	if not missing(aSAH_apc_dt) and
	   aSAH_apc_dt >= interval_window_start and
	   aSAH_apc_dt <= interval_window_end then aSAH_within_interval = 1;
	else aSAH_within_interval = 0;

	fu_days = end_of_fu - index_date + 1;

	format index_date end_of_fu interval_window_start interval_window_end aSAH_apc_dt date9.;
run;



/**************************************************************************/
/* Quick summary by index exposure                                        */
/**************************************************************************/
proc sql;
	select index_exposure,
		   count(distinct patid) as n,
		   min(fu_days) as min_fu_days,
		   max(fu_days) as max_fu_days,
		   median(fu_days) as median_fu_days,
		   mean(fu_days) as mean_fu_days,
		   sum(aSAH_within_interval) as n_asah_cases
	from output.bph_ot_all
	group by index_exposure;
quit;


data output.drugfile_subset;
set output.bphdrugatc_1 (obs = 100000);
run;

proc sort data = output.bph_ot_all;
by patid;
run;


